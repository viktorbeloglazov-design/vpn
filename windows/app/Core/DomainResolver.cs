using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;

namespace QPVPN.Core;

/// <summary>
/// Превращает домены в адреса.
///
/// Внутри России обычный DNS нередко отвечает подставными адресами, поэтому
/// сначала спрашиваем через DNS-over-HTTPS и только потом — системный
/// резолвер. Домены разбираются пачками, иначе двести с лишним имён
/// складываются в минуты ожидания.
/// </summary>
public static class DomainResolver
{
    private const int Parallel = 16;

    private static readonly string[] DohEndpoints =
    {
        "https://dns.google/resolve",
        "https://cloudflare-dns.com/dns-query",
    };

    private static readonly HttpClient Http = new(new HttpClientHandler
    {
        AutomaticDecompression = System.Net.DecompressionMethods.All,
    })
    {
        Timeout = TimeSpan.FromSeconds(6),
    };

    private static readonly ConcurrentDictionary<string, IReadOnlyList<Ipv4Net>> Cache = new();

    public static void ClearCache() => Cache.Clear();

    public static async Task<List<Ipv4Net>> ResolveAllAsync(IEnumerable<string> hosts, bool useSecureDns = true)
    {
        var unique = hosts
            .Select(host => host.Trim().ToLowerInvariant())
            .Where(host => host.Length > 0)
            .Distinct()
            .ToList();

        var result = new ConcurrentBag<Ipv4Net>();
        using var limit = new System.Threading.SemaphoreSlim(Parallel);

        var work = unique.Select(async host =>
        {
            await limit.WaitAsync().ConfigureAwait(false);
            try
            {
                foreach (var net in await ResolveAsync(host, useSecureDns).ConfigureAwait(false))
                {
                    result.Add(net);
                }
            }
            finally
            {
                limit.Release();
            }
        });

        await Task.WhenAll(work).ConfigureAwait(false);
        return result.Distinct().ToList();
    }

    private static async Task<IReadOnlyList<Ipv4Net>> ResolveAsync(string host, bool useSecureDns)
    {
        if (Cache.TryGetValue(host, out var cached)) return cached;

        var nets = new List<Ipv4Net>();
        if (useSecureDns)
        {
            nets.AddRange(await ResolveOverHttpsAsync(host).ConfigureAwait(false));
        }
        if (nets.Count == 0)
        {
            nets.AddRange(await ResolveOverSystemAsync(host).ConfigureAwait(false));
        }

        var distinct = nets.Distinct().ToList();
        if (distinct.Count > 0) Cache[host] = distinct;
        return distinct;
    }

    private static async Task<List<Ipv4Net>> ResolveOverHttpsAsync(string host)
    {
        foreach (var endpoint in DohEndpoints)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, $"{endpoint}?name={Uri.EscapeDataString(host)}&type=A");
                request.Headers.Accept.ParseAdd("application/dns-json");

                using var response = await Http.SendAsync(request).ConfigureAwait(false);
                if (!response.IsSuccessStatusCode) continue;

                await using var body = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
                using var json = await JsonDocument.ParseAsync(body).ConfigureAwait(false);
                if (!json.RootElement.TryGetProperty("Answer", out var answers)) continue;

                var nets = new List<Ipv4Net>();
                foreach (var answer in answers.EnumerateArray())
                {
                    if (!answer.TryGetProperty("type", out var type) || type.GetInt32() != 1) continue;
                    if (!answer.TryGetProperty("data", out var data)) continue;
                    if (Cidr.Parse(data.GetString() ?? "") is { } net) nets.Add(net);
                }
                if (nets.Count > 0) return nets;
            }
            catch (Exception)
            {
                // Пробуем следующий сервер, а затем системный резолвер.
            }
        }
        return new List<Ipv4Net>();
    }

    private static async Task<List<Ipv4Net>> ResolveOverSystemAsync(string host)
    {
        try
        {
            var addresses = await Dns.GetHostAddressesAsync(host).ConfigureAwait(false);
            return addresses
                .Where(address => address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                .Select(address => Cidr.Parse(address.ToString()))
                .Where(net => net is not null)
                .Select(net => net!.Value)
                .ToList();
        }
        catch (Exception)
        {
            return new List<Ipv4Net>();
        }
    }
}
