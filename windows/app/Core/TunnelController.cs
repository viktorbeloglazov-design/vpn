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

        var text = profile.ToConfigText(routes, _store.Config.UseTunnelDns, _store.Config.Mtu);

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
    /// <summary>
    /// Что уходит в туннель.
    ///
    /// Маршрутизация зашита: через VPN идёт всё, кроме российской зоны.
    /// Так заблокированный сервис открывается, даже если его адрес программе
    /// незнаком, а МАХ, госуслуги, банки и маркетплейсы работают напрямую.
    /// </summary>
    public static async Task<List<string>> RoutesForAsync(AppConfig config, WgProfile profile)
    {
        var work = await WorkNetsAsync().ConfigureAwait(false);
        var zone = FittingRuZone();

        if (config.WorkFilter)
        {
            // Рабочие ресурсы сильнее исключений: возвращаем их в туннель,
            // даже если они попали в российскую зону.
            var background = zone.Count == 0
                ? new List<Ipv4Net> { new(0, 0) }
                : Cidr.Complement(zone);
            return Cidr.Merge(background.Concat(work)).Select(net => net.ToString()).ToList();
        }

        var all = zone.Concat(work).ToList();
        return all.Count == 0
            ? new List<string> { "0.0.0.0/0" }
            : Cidr.Complement(all).Select(net => net.ToString()).ToList();
    }

    /// <summary>Столько маршрутов система принимает спокойно.</summary>
    private const int MaxRoutes = 4_000;

    /// <summary>Шаги укрупнения: какой промежуток между подсетями прощаем.</summary>
    private static readonly long[] Gaps = { 4_096, 16_384, 65_536, 262_144, 1_048_576 };

    private static List<Ipv4Net>? _cachedZone;

    /// <summary>
    /// Российская зона, ужатая до размера, который система принимает.
    ///
    /// Точный список даёт больше двадцати тысяч маршрутов: столько Windows
    /// прокладывает заметными секундами. Список укрупняется, пока маршрутов
    /// не станет разумное количество, а сервисы, которые при этом могли бы
    /// уйти мимо туннеля, возвращаются обратно.
    /// </summary>
    private static List<Ipv4Net> FittingRuZone()
    {
        if (_cachedZone is not null) return _cachedZone;

        var exact = RuZone.Networks();
        if (exact.Count == 0) return new List<Ipv4Net>();

        var keep = KeepInTunnel.Nets();
        var zone = Cidr.Subtract(exact, keep);
        var routes = Cidr.Complement(zone).Count;
        var step = 0;

        while (routes > MaxRoutes && step < Gaps.Length)
        {
            zone = Cidr.Subtract(Cidr.MergeWithGap(exact, Gaps[step]), keep);
            routes = Cidr.Complement(zone).Count;
            step++;
        }

        _cachedZone = zone;
        return zone;
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
