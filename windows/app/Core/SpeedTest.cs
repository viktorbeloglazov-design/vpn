using System;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;

namespace QPVPN.Core;

/// <summary>
/// Замер скорости — через туннель и мимо него, на одном и том же файле.
///
/// Без двух чисел разговор о скорости бессмысленный: гостевой Wi-Fi бывает
/// медленнее любого VPN, и тогда виноват не туннель. Одна и та же закачка,
/// снятая двумя путями, отвечает на вопрос сразу.
/// </summary>
public static class SpeedTest
{
    private const int Bytes = 25_000_000;
    private const int Seconds = 8;

    private static readonly string DownUrl = $"https://speed.cloudflare.com/__down?bytes={Bytes}";
    private const string UpUrl = "https://speed.cloudflare.com/__up";

    public sealed record Result(
        double DownThroughTunnel,
        double DownDirect,
        double UpThroughTunnel,
        double UpDirect,
        string Note = "")
    {
        public bool HasAny => DownThroughTunnel > 0 || DownDirect > 0;

        /// <summary>Мешает ли туннель: сравниваем, только если оба замера удались.</summary>
        public bool TunnelIsSlower =>
            (DownThroughTunnel > 0 && DownDirect > DownThroughTunnel * 1.5) ||
            (UpThroughTunnel > 0 && UpDirect > UpThroughTunnel * 1.5);
    }

    public static async Task<Result> MeasureAsync()
    {
        var bypass = PhysicalAddressOfDefaultRoute();

        var down = await DownloadAsync(null).ConfigureAwait(false);
        var downDirect = bypass is null ? 0 : await DownloadAsync(bypass).ConfigureAwait(false);
        var up = await UploadAsync(null).ConfigureAwait(false);
        var upDirect = bypass is null ? 0 : await UploadAsync(bypass).ConfigureAwait(false);

        var note = (down, downDirect) switch
        {
            ( <= 0, <= 0) => "Не удалось скачать пробный файл — сеть не отвечает.",
            (_, <= 0) => "Замерить без VPN не вышло: обычно это значит, что сеть сама его не пускает.",
            ( <= 0, _) => "Через VPN скачать не удалось — похоже, туннель не работает.",
            _ => "",
        };
        return new Result(down, downDirect, up, upDirect, note);
    }

    /// <summary>Мегабиты в секунду. 0 — не получилось.</summary>
    private static async Task<double> DownloadAsync(IPAddress? bindTo)
    {
        try
        {
            using var client = MakeClient(bindTo);
            using var cancel = new CancellationTokenSource(TimeSpan.FromSeconds(Seconds + 4));

            var watch = Stopwatch.StartNew();
            using var response = await client
                .GetAsync(DownUrl, HttpCompletionOption.ResponseHeadersRead, cancel.Token)
                .ConfigureAwait(false);
            await using var stream = await response.Content.ReadAsStreamAsync(cancel.Token).ConfigureAwait(false);

            var buffer = new byte[64 * 1024];
            long total = 0;
            while (watch.Elapsed.TotalSeconds < Seconds)
            {
                var read = await stream.ReadAsync(buffer, cancel.Token).ConfigureAwait(false);
                if (read <= 0) break;
                total += read;
            }
            watch.Stop();
            return Mbits(total, watch.Elapsed.TotalSeconds);
        }
        catch (Exception)
        {
            return 0;
        }
    }

    /// <summary>Отдача: шлём поток нулей и считаем, сколько ушло.</summary>
    private static async Task<double> UploadAsync(IPAddress? bindTo)
    {
        try
        {
            using var client = MakeClient(bindTo);
            using var cancel = new CancellationTokenSource(TimeSpan.FromSeconds(Seconds + 4));

            var watch = Stopwatch.StartNew();
            long total = 0;

            var content = new PushStreamContent(async stream =>
            {
                var buffer = new byte[64 * 1024];
                while (watch.Elapsed.TotalSeconds < Seconds && total < Bytes)
                {
                    await stream.WriteAsync(buffer, cancel.Token).ConfigureAwait(false);
                    total += buffer.Length;
                }
            });

            using var response = await client.PostAsync(UpUrl, content, cancel.Token).ConfigureAwait(false);
            watch.Stop();
            return Mbits(total, watch.Elapsed.TotalSeconds);
        }
        catch (Exception)
        {
            return 0;
        }
    }

    private static double Mbits(long bytes, double seconds) =>
        bytes <= 0 || seconds <= 0 ? 0 : bytes * 8.0 / seconds / 1_000_000.0;

    /// <summary>
    /// Клиент, привязанный к нужному сетевому адресу.
    ///
    /// Привязка к адресу настоящей сетевой карты уводит соединение мимо
    /// туннеля: так и получается второй замер, с которым есть что сравнивать.
    /// </summary>
    private static HttpClient MakeClient(IPAddress? bindTo)
    {
        var handler = new SocketsHttpHandler { UseProxy = false };
        if (bindTo is not null)
        {
            handler.ConnectCallback = async (context, token) =>
            {
                var socket = new Socket(SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
                socket.Bind(new IPEndPoint(bindTo, 0));
                try
                {
                    await socket.ConnectAsync(context.DnsEndPoint, token).ConfigureAwait(false);
                    return new NetworkStream(socket, ownsSocket: true);
                }
                catch
                {
                    socket.Dispose();
                    throw;
                }
            };
        }
        return new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(Seconds + 6) };
    }

    /// <summary>
    /// Адрес настоящей сетевой карты — не туннеля.
    ///
    /// Туннель у нас называется qpvpn, всё остальное с работающим
    /// подключением и обычным адресом годится.
    /// </summary>
    private static IPAddress? PhysicalAddressOfDefaultRoute()
    {
        foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (adapter.OperationalStatus != OperationalStatus.Up) continue;
            if (adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            if (adapter.Name.Contains("qpvpn", StringComparison.OrdinalIgnoreCase)) continue;
            if (adapter.Description.Contains("WireGuard", StringComparison.OrdinalIgnoreCase)) continue;
            if (adapter.Description.Contains("Wintun", StringComparison.OrdinalIgnoreCase)) continue;

            var address = adapter.GetIPProperties().UnicastAddresses
                .Select(entry => entry.Address)
                .FirstOrDefault(value => value.AddressFamily == AddressFamily.InterNetwork
                    && !IPAddress.IsLoopback(value));
            if (address is not null) return address;
        }
        return null;
    }

    /// <summary>«12.3 Мбит/с» — в таком виде число понятно без пояснений.</summary>
    public static string Format(double mbits) => mbits switch
    {
        <= 0 => "—",
        >= 100 => $"{(int)mbits} Мбит/с",
        _ => $"{Math.Max(mbits, 0.1):0.0} Мбит/с",
    };
}

/// <summary>Тело запроса, которое пишется на ходу: для замера отдачи.</summary>
internal sealed class PushStreamContent : HttpContent
{
    private readonly Func<System.IO.Stream, Task> _write;

    public PushStreamContent(Func<System.IO.Stream, Task> write) => _write = write;

    protected override Task SerializeToStreamAsync(System.IO.Stream stream, TransportContext? context) =>
        _write(stream);

    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        return false;
    }
}
