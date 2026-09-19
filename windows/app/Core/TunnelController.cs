using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace QPVPN.Core;

public enum ConnectionState
{
    Disconnected,
    Connecting,
    Connected,
    Error,
}

public sealed record TunnelStatus(
    ConnectionState State = ConnectionState.Disconnected,
    string Message = "",
    long RxBytes = 0,
    long TxBytes = 0,
    int RouteCount = 0,
    string ServerName = "");

/// <summary>
/// Поднимает и снимает туннель.
///
/// Сам туннель держит отдельная служба Windows (qpvpn-tunnel.exe на
/// библиотеке AmneziaWG): здесь считаются маршруты, пишется файл настроек
/// и отдаются команды службе.
/// </summary>
public sealed class TunnelController
{
    private const string TunnelName = "qpvpn";

    private readonly Store _store;

    public TunnelController(Store store) => _store = store;

    public TunnelStatus Status { get; private set; } = new();

    private static string ToolPath => Path.Combine(
        AppContext.BaseDirectory, "qpvpn-tunnel.exe");

    // MARK: - Управление

    public async Task<TunnelStatus> ConnectAsync()
    {
        var profileText = _store.ProfileText();
        if (string.IsNullOrWhiteSpace(profileText))
        {
            return Status = new TunnelStatus(ConnectionState.Error,
                "Профиль не загружен: добавьте ключ vpn://, QR-код или файл .conf.");
        }

        WgProfile profile;
        try
        {
            profile = WgProfile.Parse(profileText);
        }
        catch (Exception error)
        {
            return Status = new TunnelStatus(ConnectionState.Error, error.Message);
        }

        Status = new TunnelStatus(ConnectionState.Connecting);

        List<string> routes;
        try
        {
            routes = await RoutesForAsync(_store.Config, profile).ConfigureAwait(false);
        }
        catch (Exception error)
        {
            return Status = new TunnelStatus(ConnectionState.Error, $"Маршруты не посчитались: {error.Message}");
        }

        var text = profile.ToConfigText(routes, _store.Config.UseTunnelDns && _store.Config.EffectiveMode != TunnelMode.Include);

        try
        {
            WriteTunnelConfig(text);
        }
        catch (Exception error)
        {
            return Status = new TunnelStatus(ConnectionState.Error, $"Не удалось сохранить настройки туннеля: {error.Message}");
        }

        var (code, _, stderr) = await RunToolAsync("/installtunnelservice", Store.ProfilePath).ConfigureAwait(false);
        if (code != 0)
        {
            return Status = new TunnelStatus(ConnectionState.Error,
                stderr.Length > 0 ? stderr : "Служба туннеля не запустилась.");
        }

        return Status = new TunnelStatus(
            ConnectionState.Connected,
            RouteCount: routes.Count,
            ServerName: profile.EndpointHost);
    }

    public async Task<TunnelStatus> DisconnectAsync()
    {
        await RunToolAsync("/uninstalltunnelservice", TunnelName).ConfigureAwait(false);
        return Status = new TunnelStatus();
    }

    /// <summary>Спрашивает службу, жива ли она и сколько прошло трафика.</summary>
    public async Task<TunnelStatus> RefreshAsync()
    {
        var (code, stdout, _) = await RunToolAsync("/status", TunnelName).ConfigureAwait(false);
        if (code != 0 || stdout.Length == 0) return Status;

        try
        {
            using var json = JsonDocument.Parse(stdout);
            var root = json.RootElement;
            var running = root.GetProperty("running").GetBoolean();
            var rx = root.TryGetProperty("rxBytes", out var rxValue) ? rxValue.GetInt64() : 0;
            var tx = root.TryGetProperty("txBytes", out var txValue) ? txValue.GetInt64() : 0;

            if (!running && Status.State == ConnectionState.Connected)
            {
                return Status = new TunnelStatus(ConnectionState.Disconnected);
            }
            if (running)
            {
                return Status = Status with
                {
                    State = ConnectionState.Connected,
                    RxBytes = rx,
                    TxBytes = tx,
                };
            }
        }
        catch (JsonException)
        {
            // Служба ответила не по форме — состояние оставляем прежним.
        }
        return Status;
    }

    // MARK: - Маршруты

    /// <summary>Считает список подсетей, которые должны уходить в туннель.</summary>
    public static async Task<List<string>> RoutesForAsync(AppConfig config, WgProfile profile)
    {
        var nets = await ResolveRulesAsync(config).ConfigureAwait(false);
        var work = await WorkNetsAsync().ConfigureAwait(false);

        switch (config.EffectiveMode)
        {
            case TunnelMode.Full:
                if (config.WorkFilter || work.Count == 0) return new List<string> { "0.0.0.0/0" };
                // Рабочие ресурсы выключены — вычитаем их из полного туннеля.
                return Cidr.Complement(work).Select(net => net.ToString()).ToList();

            case TunnelMode.Include:
            {
                var included = config.WorkFilter ? nets.Concat(work).ToList() : nets;
                if (included.Count == 0)
                {
                    // Пустой список туннель не примет: оставляем адрес самого клиента.
                    var address = profile.Addresses.FirstOrDefault()?.Split('/')[0];
                    return new List<string> { address is null ? "0.0.0.0/32" : $"{address}/32" };
                }
                return Cidr.Merge(included).Select(net => net.ToString()).ToList();
            }

            default:
            {
                var excluded = config.BypassRuZone
                    ? nets.Concat(RuZone.Networks()).ToList()
                    : nets;

                if (config.WorkFilter)
                {
                    // Рабочие ресурсы сильнее исключений: возвращаем их в туннель.
                    var background = excluded.Count == 0
                        ? new List<Ipv4Net> { new(0, 0) }
                        : Cidr.Complement(excluded);
                    return Cidr.Merge(background.Concat(work)).Select(net => net.ToString()).ToList();
                }

                var all = excluded.Concat(work).ToList();
                return all.Count == 0
                    ? new List<string> { "0.0.0.0/0" }
                    : Cidr.Complement(all).Select(net => net.ToString()).ToList();
            }
        }
    }

    /// <summary>
    /// Разворачивает правила в адреса. Когда включён главный фильтр,
    /// к правилам добавляется встроенный список сервисов.
    /// </summary>
    private static async Task<List<Ipv4Net>> ResolveRulesAsync(AppConfig config)
    {
        var result = new List<Ipv4Net>();
        var domains = new List<string>();

        foreach (var rule in config.ActiveRules)
        {
            if (rule.Kind == RuleKind.Cidr)
            {
                if (Cidr.Parse(rule.Value) is { } net) result.Add(net);
            }
            else
            {
                domains.Add(rule.Value.Trim().ToLowerInvariant());
            }
        }

        if (config.MainFilter) domains.AddRange(MasterFilter.Domains);

        if (domains.Count > 0)
        {
            result.AddRange(await DomainResolver.ResolveAllAsync(domains).ConfigureAwait(false));
        }
        return result.Distinct().ToList();
    }

    /// <summary>Адреса рабочих ресурсов: заложенные в приложение узлы.</summary>
    private static async Task<List<Ipv4Net>> WorkNetsAsync()
    {
        var result = new List<Ipv4Net>();
        var domains = new List<string>();

        foreach (var host in WorkFilter.Hosts)
        {
            if (Cidr.Parse(host) is { } net) result.Add(net);
            else domains.Add(host.ToLowerInvariant());
        }

        if (domains.Count > 0)
        {
            result.AddRange(await DomainResolver.ResolveAllAsync(domains).ConfigureAwait(false));
        }
        return result.Distinct().ToList();
    }

    // MARK: - Файлы и запуск

    /// <summary>
    /// Кладёт настройки туда, где их прочитает служба.
    ///
    /// В файле лежит приватный ключ, поэтому доступ к нему оставляем только
    /// администраторам и системе: обычные программы и другие пользователи
    /// компьютера его не увидят.
    /// </summary>
    public static void WriteTunnelConfig(string text)
    {
        Directory.CreateDirectory(Store.TunnelDirectory);
        File.WriteAllText(Store.ProfilePath, text, new UTF8Encoding(false));
        RestrictAccess(Store.ProfilePath);
    }

    private static void RestrictAccess(string path)
    {
        try
        {
            // Известные SID вместо имён: они одинаковы на любом языке Windows.
            var arguments = $"\"{path}\" /inheritance:r /grant *S-1-5-32-544:(F) /grant *S-1-5-18:(F)";
            var info = new ProcessStartInfo("icacls", arguments)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            using var process = Process.Start(info);
            process?.WaitForExit(10_000);
        }
        catch (Exception)
        {
            // Права остались наследованными: ключ виден администраторам
            // компьютера. Это не мешает работе туннеля.
        }
    }

    private static async Task<(int Code, string Stdout, string Stderr)> RunToolAsync(params string[] arguments)
    {
        var info = new ProcessStartInfo(ToolPath)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var argument in arguments) info.ArgumentList.Add(argument);

        try
        {
            using var process = Process.Start(info);
            if (process is null) return (1, "", "Не удалось запустить служебную программу туннеля.");

            var stdout = await process.StandardOutput.ReadToEndAsync().ConfigureAwait(false);
            var stderr = await process.StandardError.ReadToEndAsync().ConfigureAwait(false);
            await process.WaitForExitAsync().ConfigureAwait(false);
            return (process.ExitCode, stdout.Trim(), stderr.Trim());
        }
        catch (Exception error)
        {
            return (1, "", error.Message);
        }
    }
}
