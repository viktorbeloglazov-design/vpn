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

        var config = _store.Config;
        var endpoints = config.EndpointsToTry(profile.Endpoint);
        var text = profile.ToConfigText(routes, config.UseTunnelDns, config.Mtu);

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

        // Служба запущена — но это ещё не связь. «Подключён» ставится
        // только после того, как сервер ответил: иначе человек видит
        // зелёную надпись и гадает, почему ничего не открывается.
        Status = new TunnelStatus(
            ConnectionState.Connecting,
            RouteCount: routes.Count,
            ServerName: profile.EndpointHost);

        await VerifyAndTuneAsync(profile, routes, endpoints).ConfigureAwait(false);
        return Status;
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

    /// <summary>Каким входом поднялась связь и с каким размером пакета.</summary>
    public bool UsedBackupEntry { get; private set; }

    public int ActiveMtu { get; private set; }

    /// <summary>
    /// Сколько ждать, пока поднятый туннель начнёт работать.
    ///
    /// Служба запускается не мгновенно: ей нужно создать сетевой адаптер,
    /// задать адрес, проложить маршруты и обменяться приветствием
    /// с сервером. Маршрутов тысячи, и на медленной машине это секунды.
    /// </summary>
    private static readonly TimeSpan ReadyTimeout = TimeSpan.FromSeconds(25);

    /// <summary>
    /// Ждёт, пока туннель действительно заработает.
    ///
    /// Раньше этого ожидания не было: проверка связи запускалась сразу
    /// после команды на запуск службы, когда туннеля ещё не существовало.
    /// Она, конечно, не проходила — и программа принималась перебирать
    /// размеры пакета, переустанавливая службу снова и снова. Туннелю
    /// не давали подняться ни разу: отправка шла, ответа не было,
    /// и адрес не определялся.
    /// </summary>
    /// <returns>true — сервер ответил.</returns>
    private async Task<bool> WaitUntilReadyAsync()
    {
        var deadline = DateTimeOffset.UtcNow + ReadyTimeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            await Task.Delay(700).ConfigureAwait(false);

            var (code, stdout, _) = await RunToolAsync("/status", TunnelName).ConfigureAwait(false);
            if (code != 0) continue;

            if (TunnelReadiness.Parse(stdout).IsReady) return true;
        }
        return false;
    }

    /// <summary>
    /// Доводит поднятый туннель до рабочего состояния.
    ///
    /// Сначала дожидаемся, пока туннель вообще заработает, и только потом
    /// проверяем, идут ли через него большие порции данных. Не идут —
    /// перебираем размеры пакета, а затем запасной вход. Каждая попытка —
    /// это перезапуск службы, поэтому их порядок считается заранее
    /// и лишних не делается.
    ///
    /// Если не помогло ничего, возвращаем ту настройку, с которой начинали:
    /// оставить человека с последней неудачной — значит оставить его вовсе
    /// без связи.
    /// </summary>
    private async Task VerifyAndTuneAsync(WgProfile profile, List<string> routes, List<string> endpoints)
    {
        var config = _store.Config;
        UsedBackupEntry = false;
        var firstMtu = config.Mtu > 0 ? config.Mtu : profile.Mtu;

        if (await WaitUntilReadyAsync().ConfigureAwait(false)
            && await BulkCheck.WorksAsync().ConfigureAwait(false))
        {
            ActiveMtu = firstMtu;
            Status = Status with { State = ConnectionState.Connected, Message = "" };
            return;
        }

        var attempts = TuningPlan.Build(endpoints, profile.Mtu, config.Mtu, config.ProbedMtu);
        foreach (var attempt in attempts)
        {
            if (!await ApplyAsync(profile, routes, attempt.Endpoint, attempt.Mtu).ConfigureAwait(false))
            {
                continue;
            }
            if (!await BulkCheck.WorksAsync().ConfigureAwait(false)) continue;

            UsedBackupEntry = attempt.ViaBackup;
            ActiveMtu = attempt.Mtu;
            if (config.Mtu == 0 && attempt.Mtu != config.ProbedMtu)
            {
                _store.Config.ProbedMtu = attempt.Mtu;
                _store.Save();
            }
            Status = Status with
            {
                State = ConnectionState.Connected,
                ServerName = HostOf(attempt.Endpoint),
                Message = attempt.ViaBackup ? "Через запасной вход" : "",
            };
            return;
        }

        // Ничего не подошло. Возвращаем исходную настройку: пусть связь
        // и неидеальна, но это лучше, чем брошенная посередине перебора
        // служба, с которой не работает ничего.
        var restored = await ApplyAsync(profile, routes, endpoints[0], firstMtu).ConfigureAwait(false);
        ActiveMtu = firstMtu;
        Status = Status with
        {
            // Сервер ответил, но крупные порции данных не проходят —
            // связь есть, пользоваться ею тяжело. Это не то же самое,
            // что «туннель не поднялся».
            State = restored ? ConnectionState.Connected : ConnectionState.Error,
            ServerName = profile.EndpointHost,
            Message = restored
                ? "Связь нестабильна — проверьте сеть или задайте запасной вход"
                : "Сервер не отвечает. Проверьте ключ и подключение к интернету.",
        };
    }

    /// <summary>
    /// Переподнимает туннель с другим входом или размером пакета.
    /// </summary>
    /// <returns>true — служба запустилась и сервер ответил.</returns>
    private async Task<bool> ApplyAsync(WgProfile profile, List<string> routes, string endpoint, int mtu)
    {
        var attempt = profile with { Endpoint = endpoint };
        try
        {
            WriteTunnelConfig(attempt.ToConfigText(routes, _store.Config.UseTunnelDns, mtu));
        }
        catch (Exception)
        {
            return false;
        }

        await RunToolAsync("/uninstalltunnelservice", TunnelName).ConfigureAwait(false);
        var (code, _, _) = await RunToolAsync("/installtunnelservice", Store.ProfilePath)
            .ConfigureAwait(false);
        if (code != 0) return false;

        return await WaitUntilReadyAsync().ConfigureAwait(false);
    }

    /// <summary>Имя узла из адреса вида «адрес:порт».</summary>
    private static string HostOf(string endpoint)
    {
        var colon = endpoint.LastIndexOf(':');
        return colon > 0 ? endpoint[..colon] : endpoint;
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
