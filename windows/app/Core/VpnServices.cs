using System.Collections.Generic;
using System.Linq;

namespace QPVPN.Core;

/// <summary>
/// Сервисы, ради которых включают VPN: ChatGPT, Claude, YouTube, WhatsApp.
///
/// Один переключатель в окне управляет именно этим списком. Всё, чего здесь
/// нет, идёт мимо VPN напрямую — российские сайты, банки, маркетплейсы,
/// МАХ, госуслуги, рабочая почта.
///
/// Адреса подобраны по одному правилу: в список попадают только те сети,
/// которые принадлежат самим этим сервисам. Сети посредников — Cloudflare,
/// Google Cloud, — куда более широкие: на них стоят десятки тысяч чужих
/// сайтов, в том числе российских, и заворачивать их в туннель нельзя.
/// Поэтому ChatGPT, который целиком живёт на Cloudflare, ходит через VPN
/// по точным адресам из DNS, а не по чужим сетям.
/// </summary>
public static class VpnServices
{
    /// <param name="Title">Как называется в окне.</param>
    /// <param name="Networks">Собственные сети сервиса.</param>
    /// <param name="Domains">Имена, чьи адреса спрашиваем у DNS.</param>
    /// <param name="Suffixes">Имена, которые надо разрешать через VPN.</param>
    public sealed record Service(string Title, string[] Networks, string[] Domains, string[] Suffixes);

    public static readonly IReadOnlyList<Service> Services = new List<Service>
    {
        // Собственных сетей у ChatGPT нет: и сайт, и обращения программ
        // идут через Cloudflare, где рядом стоят чужие сайты. Поэтому
        // только точные адреса, полученные у DNS, и память прошлых адресов.
        new("ChatGPT", [],
            ["chatgpt.com", "www.chatgpt.com", "ab.chatgpt.com", "auth.openai.com",
             "chat.openai.com", "openai.com", "www.openai.com", "api.openai.com",
             "auth0.openai.com", "platform.openai.com", "cdn.oaistatic.com",
             "files.oaiusercontent.com", "videos.openai.com", "sora.chatgpt.com"],
            ["chatgpt.com", ".chatgpt.com", "openai.com", ".openai.com",
             ".oaistatic.com", ".oaiusercontent.com"]),

        // Anthropic держит свою сеть: и claude.ai, и обращения программ
        // отвечают с неё, чужого на ней нет.
        new("Claude", ["160.79.104.0/23"],
            ["claude.ai", "www.claude.ai", "claude.com", "www.claude.com",
             "anthropic.com", "www.anthropic.com", "api.anthropic.com",
             "console.anthropic.com"],
            ["claude.ai", ".claude.ai", "claude.com", ".claude.com",
             "anthropic.com", ".anthropic.com"]),

        // YouTube отдаёт видео с серверов, имена которых каждый раз новые
        // (rr3---sn-… .googlevideo.com), перечислить их нельзя. Зато все они
        // стоят в собственных сетях Google — их и берём.
        new("YouTube", Google,
            ["www.youtube.com", "youtube.com", "m.youtube.com", "youtu.be",
             "i.ytimg.com", "s.ytimg.com", "yt3.ggpht.com",
             "youtubei.googleapis.com", "redirector.googlevideo.com",
             "manifest.googlevideo.com"],
            ["youtube.com", ".youtube.com", ".googlevideo.com", ".ytimg.com",
             ".ggpht.com", "youtu.be", ".youtu.be"]),

        // WhatsApp — сети самой Meta.
        new("WhatsApp", Meta,
            ["web.whatsapp.com", "www.whatsapp.com", "whatsapp.com",
             "static.whatsapp.net", "mmg.whatsapp.net", "g.whatsapp.net",
             "media.whatsapp.net"],
            ["whatsapp.com", ".whatsapp.com", "whatsapp.net", ".whatsapp.net"]),
    };

    /// <summary>
    /// Собственные сети Google: поиск, YouTube и раздача видео.
    ///
    /// Сетей Google Cloud здесь нарочно нет. Google Cloud сдаётся в аренду,
    /// и на нём стоят чужие сайты, включая российские: заверни их в туннель —
    /// и они поедут через Казахстан вместо прямого пути.
    /// </summary>
    private static string[] Google =>
    [
        "64.233.160.0/19", "66.102.0.0/20", "66.249.64.0/19", "72.14.192.0/18",
        "74.125.0.0/16", "108.177.0.0/17", "142.250.0.0/15", "142.251.0.0/16",
        "172.217.0.0/16", "172.253.0.0/16", "173.194.0.0/16", "192.178.0.0/15",
        "207.223.160.0/20", "209.85.128.0/17", "216.58.192.0/19", "216.239.32.0/19",
        "208.65.152.0/22", "208.68.108.0/22",
    ];

    /// <summary>Сети Meta: на них живёт WhatsApp.</summary>
    private static string[] Meta =>
    [
        "31.13.24.0/21", "31.13.64.0/18", "45.64.40.0/22", "57.144.0.0/14",
        "66.220.144.0/20", "69.63.176.0/20", "69.171.224.0/19", "74.119.76.0/22",
        "103.4.96.0/22", "129.134.0.0/16", "157.240.0.0/16", "173.252.64.0/18",
        "179.60.192.0/22", "185.60.216.0/22", "204.15.20.0/22",
    ];

    /// <summary>
    /// Сети владельцев сервисов — только для проверки ответа DNS.
    ///
    /// В туннель эти сети НЕ уходят: они слишком широкие, на них стоят
    /// чужие сайты. Но они отвечают на другой вопрос: настоящий ли адрес
    /// назвал DNS. На заблокированное имя провайдер нередко отвечает
    /// адресом своей заглушки — адрес живой, публичный, российский.
    /// Запомнить его и проложить в туннель значит увести туда чужой
    /// трафик, поэтому берутся только адреса из сетей самих владельцев:
    /// Cloudflare, Google, Meta, Anthropic.
    /// </summary>
    private static string[] Owners =>
        [.. Cloudflare, .. Google, .. Meta, "160.79.104.0/23"];

    /// <summary>Сети Cloudflare: на них стоит ChatGPT — и чужие сайты тоже.</summary>
    private static string[] Cloudflare =>
    [
        "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
        "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
        "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
        "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    ];

    private static readonly Ipv4Net[] OwnerNets = Owners
        .Select(Cidr.Parse)
        .Where(net => net is not null)
        .Select(net => net!.Value)
        .ToArray();

    /// <summary>
    /// Похоже ли на настоящий адрес сервиса.
    ///
    /// Проверка нужна ровно в одном месте: прежде чем запомнить ответ DNS
    /// и проложить к нему маршрут.
    /// </summary>
    public static bool IsServiceAddress(Ipv4Net net) =>
        Cidr.IsPublicAddress(net)
        && OwnerNets.Any(owner => net.Start >= owner.Start && net.Start <= owner.EndInclusive);

    /// <summary>Все подсети списка одним набором.</summary>
    public static List<Ipv4Net> Nets() => Services
        .SelectMany(service => service.Networks)
        .Select(Cidr.Parse)
        .Where(net => net is not null)
        .Select(net => net!.Value)
        .ToList();

    /// <summary>Имена, которые стоит спросить у DNS: адреса меняются.</summary>
    public static List<string> Domains() =>
        Services.SelectMany(service => service.Domains).Distinct().ToList();

    /// <summary>Имена, которые надо разрешать через VPN, а не у провайдера.</summary>
    public static List<string> Suffixes() =>
        Services.SelectMany(service => service.Suffixes).Distinct().ToList();

    public static IReadOnlyList<string> Titles =>
        Services.Select(service => service.Title).ToList();
}
