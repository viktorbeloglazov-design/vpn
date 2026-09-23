using System.Collections.Generic;
using System.Linq;

namespace QPVPN.Core;

/// <summary>
/// Сервисы, ради которых включают VPN.
///
/// Один переключатель в окне управляет именно этим списком: включён —
/// перечисленное идёт через VPN, выключен — вообще весь трафик идёт мимо.
///
/// Адресов мало не бывает: эти сервисы живут на сетях доставки, и один
/// и тот же сайт отвечает с десятков разных адресов, меняющихся по ходу
/// дела. Поэтому в списке не отдельные адреса, а целые подсети их
/// владельцев — Cloudflare, Google, Meta, Anthropic. Проверено на живых
/// ответах: все адреса, которые сейчас отдают эти сайты, сюда попадают.
/// </summary>
public static class VpnServices
{
    public sealed record Service(string Title, string[] Networks, string[] Domains);

    public static readonly IReadOnlyList<Service> Services = new List<Service>
    {
        new("ChatGPT", Cloudflare, ["chatgpt.com", "chat.openai.com", "api.openai.com",
                                    "auth0.openai.com", "cdn.oaistatic.com"]),

        new("Claude", ["160.79.104.0/23"], ["claude.ai", "api.anthropic.com",
                                            "console.anthropic.com"]),

        new("WhatsApp", Meta, ["web.whatsapp.com", "www.whatsapp.com", "static.whatsapp.net"]),

        new("YouTube", Google, ["www.youtube.com", "youtube.com", "m.youtube.com",
                                "i.ytimg.com", "youtubei.googleapis.com"]),
    };

    /// <summary>Сети Cloudflare: на них живут ChatGPT и многое другое.</summary>
    private static string[] Cloudflare =>
    [
        "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
        "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
        "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
        "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    ];

    /// <summary>Сети Google: сам YouTube и раздача видео.</summary>
    private static string[] Google =>
    [
        "8.34.208.0/20", "8.35.192.0/20", "23.236.48.0/20", "23.251.128.0/19",
        "34.64.0.0/10", "35.184.0.0/13", "64.233.160.0/19", "66.102.0.0/20",
        "66.249.64.0/19", "70.32.128.0/19", "72.14.192.0/18", "74.125.0.0/16",
        "108.177.0.0/17", "130.211.0.0/16", "136.22.160.0/20", "142.250.0.0/15",
        "142.251.0.0/16", "146.148.0.0/17", "172.110.32.0/21", "172.217.0.0/16",
        "172.253.0.0/16", "173.194.0.0/16", "192.178.0.0/15", "199.36.154.0/23",
        "207.223.160.0/20", "208.65.152.0/22", "208.68.108.0/22", "209.85.128.0/17",
        "216.58.192.0/19", "216.239.32.0/19",
    ];

    /// <summary>Сети Meta: на них живёт WhatsApp.</summary>
    private static string[] Meta =>
    [
        "31.13.24.0/21", "31.13.64.0/18", "45.64.40.0/22", "57.144.0.0/14",
        "66.220.144.0/20", "69.63.176.0/20", "69.171.224.0/19", "74.119.76.0/22",
        "103.4.96.0/22", "129.134.0.0/16", "157.240.0.0/16", "173.252.64.0/18",
        "179.60.192.0/22", "185.60.216.0/22", "204.15.20.0/22",
    ];

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

    public static IReadOnlyList<string> Titles =>
        Services.Select(service => service.Title).ToList();
}
