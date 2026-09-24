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

    public async Task<TunnelStatus> ConnectAsync(IProgress<string>? progress = null)
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
            progress?.Report("Считаю маршруты…");
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

        progress?.Report("Поднимаю туннель…");
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

        await VerifyAndTuneAsync(profile, routes, endpoints, progress).ConfigureAwait(false);

        // Имена сервисов разрешаем через туннель только при живой связи:
        // правило, оставшееся при мёртвом туннеле, лишило бы эти сайты
        // адресов вовсе.
        if (Status.State == ConnectionState.Connected)
        {
            SplitDns.Apply(_store.Config.ServicesThroughVpn);
        }
        else
        {
            SplitDns.Remove();
        }

        return Status;
    }

    public async Task<TunnelStatus> DisconnectAsync()
    {
        SplitDns.Remove();
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
            var report = TunnelReadiness.Parse(stdout);

            if (!report.Running)
            {
                if (Status.State != ConnectionState.Connected) return Status;

                // Туннель пропал — снимаем правило разрешения имён, иначе
                // ChatGPT и YouTube перестанут открываться вообще.
                SplitDns.Remove();
                return Status = new TunnelStatus(ConnectionState.Disconnected);
            }

            // Запущенная служба — это ещё не связь. Пока сервер не ответил,
            // писать «Подключён» нельзя: раньше так и было, и человек видел
            // зелёную надпись при нулевом приёме, гадая, почему ничего
            // не открывается.
            return Status = Status with
            {
                State = report.IsReady ? ConnectionState.Connected : ConnectionState.Connecting,
                RxBytes = report.RxBytes,
                TxBytes = report.TxBytes,
                Message = report.IsReady
                    ? (Status.State == ConnectionState.Connected ? Status.Message : "")
                    : "Сервер не отвечает — идёт подключение…",
            };
        }
        catch (JsonException)
        {
            // Служба ответила не по форме — состояние оставляем прежним.
        }
        return Status;
    }

    // MARK: - Маршруты

    /// <summary>
    /// Что уходит в туннель.
    ///
    /// Через VPN идёт только перечисленное: рабочая зона для 1С и, если
    /// включён переключатель, четыре сервиса. Всё остальное — российские
    /// сайты, банки, маркетплейсы, МАХ, госуслуги, почта — идёт напрямую,
    /// мимо туннеля.
    /// </summary>
    public static async Task<List<string>> RoutesForAsync(AppConfig config, WgProfile profile)
    {
        _ = profile;

        // Рабочая зона для 1С идёт через VPN всегда: без доступа к базе
        // работать нельзя, и выбирать тут нечего.
        var nets = await ResolveAsync(OneCZone.Hosts).ConfigureAwait(false);

        // Переключатель в окне управляет вторым списком. Выключен — через
        // VPN идёт только 1С, весь остальной трафик уходит мимо туннеля.
        if (config.ServicesThroughVpn)
        {
            nets.AddRange(VpnServices.Nets());

            // Серверы имён, у которых спрашиваем адреса сервисов: вопрос
            // тоже должен уйти через туннель, иначе вернётся ответ
            // провайдера, ради обхода которого всё и затевалось.
            nets.AddRange(SplitDnsRules.ServerNets());

            nets.AddRange(await ServiceAddressesAsync().ConfigureAwait(false));
        }

        if (nets.Count == 0)
        {
            // Пустой список туннель не примет. Ставим адрес самого клиента:
            // он никуда не ведёт, туннель просто стоит пустым.
            var address = profile.Addresses.FirstOrDefault() ?? "10.0.0.1/32";
            var slash = address.IndexOf('/');
            return [slash > 0 ? address : address + "/32"];
        }

        return Cidr.Merge(nets).Select(net => net.ToString()).ToList();
    }

    /// <summary>
    /// Точные адреса сервисов: свежий ответ DNS плюс память прошлых.
    ///
    /// У ChatGPT собственных сетей нет — он стоит на Cloudflare рядом
    /// с чужими сайтами, и взять сети Cloudflare целиком нельзя: вместе
    /// с ним в туннель уехали бы российские сайты, которые там тоже живут.
    /// Поэтому берутся ровно те адреса, которые назвал DNS.
    ///
    /// Адреса эти со временем меняются, а узнаём мы о смене только при
    /// подключении. Чтобы вчерашний адрес не пропадал, увиденное
    /// запоминается на месяц: помнить лишний адрес сервиса безвредно,
    /// а потерять нужный — значит остаться без ChatGPT до переподключения.
    /// </summary>
    private static async Task<List<Ipv4Net>> ServiceAddressesAsync()
    {
        var fresh = await WithinBudgetAsync(ResolveAsync(VpnServices.Domains()),
                                            ResolveBudget).ConfigureAwait(false);

        // В память идут только адреса из сетей владельцев сервисов.
        // На заблокированное имя провайдер нередко отвечает адресом своей
        // заглушки: адрес живой и публичный, но сервису не принадлежит —
        // проложить к нему маршрут значит увести в туннель чужое.
        var honest = fresh.Where(VpnServices.IsServiceAddress).ToList();

        var remembered = KnownAddresses.Merge(
            KnownAddresses.Load(),
            honest.Select(net => net.ToString().Split('/')[0]),
            DateTimeOffset.UtcNow);
        KnownAddresses.Save(remembered);

        var result = new List<Ipv4Net>(honest);
        result.AddRange(KnownAddresses.Nets(remembered));
        return result;
    }

    /// <summary>
    /// Сколько всего можно потратить на выяснение адресов.
    ///
    /// Имена спрашиваются у публичных серверов по защищённому каналу, и в
    /// сетях, где такой канал прикрыт, каждый вопрос упирается в ожидание.
    /// Тридцать с лишним имён — и человек сидит перед надписью «Считаю
    /// маршруты…» дольше минуты, решая, что программа повисла.
    ///
    /// Подключение важнее полноты списка: чего не успели спросить, то
    /// возьмётся из памяти адресов и из сетей самих сервисов.
    /// </summary>
    private static readonly TimeSpan ResolveBudget = TimeSpan.FromSeconds(12);

    /// <summary>Ждёт результат, но не дольше отведённого времени.</summary>
    private static async Task<List<Ipv4Net>> WithinBudgetAsync(Task<List<Ipv4Net>> work, TimeSpan budget)
    {
        var finished = await Task.WhenAny(work, Task.Delay(budget)).ConfigureAwait(false);
        if (!ReferenceEquals(finished, work)) return new List<Ipv4Net>();

        try
        {
            return await work.ConfigureAwait(false);
        }
        catch (Exception)
        {
            return new List<Ipv4Net>();
        }
    }

    /// <summary>
    /// Превращает список узлов в подсети: адреса берём как есть, имена
    /// спрашиваем у DNS.
    /// </summary>
    private static async Task<List<Ipv4Net>> ResolveAsync(IEnumerable<string> hosts)
    {
        var result = new List<Ipv4Net>();
        var domains = new List<string>();

        foreach (var host in hosts)
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
    private static readonly TimeSpan ReadyTimeout = TimeSpan.FromSeconds(20);

    /// <summary>
    /// Сколько ждать при повторных попытках.
    ///
    /// Первый раз туннель поднимается дольше всего: создаётся адаптер,
    /// прокладываются маршруты. При переподключении всё это уже сделано,
    /// и если сервер не ответил за восемь секунд — он не ответит и за
    /// двадцать, а человек всё это время сидит без связи.
    /// </summary>
    private static readonly TimeSpan RetryReadyTimeout = TimeSpan.FromSeconds(8);

    /// <summary>
    /// Сколько всего можно потратить на подбор.
    ///
    /// Восемь попыток по двадцать секунд — это почти три минуты молчания,
    /// за которые человек успевает решить, что программа повисла. Лучше
    /// честно сказать, что не вышло, чем перебирать до бесконечности.
    /// </summary>
    private static readonly TimeSpan TuningBudget = TimeSpan.FromSeconds(75);

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
    private async Task<bool> WaitUntilReadyAsync(TimeSpan? limit = null)
    {
        var deadline = DateTimeOffset.UtcNow + (limit ?? ReadyTimeout);
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
    private async Task VerifyAndTuneAsync(WgProfile profile, List<string> routes,
                                          List<string> endpoints, IProgress<string>? progress)
    {
        var config = _store.Config;
        UsedBackupEntry = false;
        var firstMtu = config.Mtu > 0 ? config.Mtu : profile.Mtu;

        progress?.Report("Жду ответа сервера…");
        if (await WaitUntilReadyAsync().ConfigureAwait(false))
        {
            progress?.Report("Сервер ответил, проверяю связь…");
            if (await BulkCheck.WorksAsync().ConfigureAwait(false))
            {
                ActiveMtu = firstMtu;
                Status = Status with { State = ConnectionState.Connected, Message = "" };
                return;
            }
        }

        var deadline = DateTimeOffset.UtcNow + TuningBudget;
        var attempts = TuningPlan.Build(endpoints, profile.Mtu, config.Mtu, config.ProbedMtu);
        var number = 0;

        foreach (var attempt in attempts)
        {
            number++;
            if (DateTimeOffset.UtcNow > deadline) break;

            progress?.Report(attempt.ViaBackup
                ? $"Пробую запасной вход, пакет {attempt.Mtu} ({number} из {attempts.Count})…"
                : $"Пробую размер пакета {attempt.Mtu} ({number} из {attempts.Count})…");

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
        progress?.Report("Возвращаю исходные настройки…");
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

        return await WaitUntilReadyAsync(RetryReadyTimeout).ConfigureAwait(false);
    }

    /// <summary>Имя узла из адреса вида «адрес:порт».</summary>
    private static string HostOf(string endpoint)
    {
        var colon = endpoint.LastIndexOf(':');
        return colon > 0 ? endpoint[..colon] : endpoint;
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
