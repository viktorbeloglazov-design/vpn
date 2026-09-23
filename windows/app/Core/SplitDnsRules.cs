using System.Collections.Generic;
using System.Linq;

namespace QPVPN.Core;

/// <summary>
/// Правило «эти имена спрашивать через VPN».
///
/// Зачем это нужно. Провайдер отвечает на запрос об адресе так, как ему
/// удобно: для YouTube он обычно называет свой ближайший кэш, а этот кэш
/// как раз и придушен — видео крутится и не грузится. Адрес при этом
/// российский, в туннель он не попадает, и включённый VPN ничем не
/// помогает.
///
/// Поэтому имена четырёх сервисов — и только они — спрашиваются у
/// публичных серверов имён через туннель. Все остальные имена, включая
/// российские сайты и рабочую почту, разрешаются как раньше, у провайдера:
/// своих имён он знает лучше и отвечает быстрее.
/// </summary>
public static class SplitDnsRules
{
    /// <summary>У кого спрашиваем имена сервисов: Google и Cloudflare.</summary>
    public static readonly string[] Servers = { "8.8.8.8", "1.1.1.1" };

    /// <summary>Имена, которые уходят на эти серверы.</summary>
    public static List<string> Names(bool servicesThroughVpn) =>
        servicesThroughVpn ? VpnServices.Suffixes() : new List<string>();

    /// <summary>
    /// Сами серверы имён тоже должны идти через туннель.
    ///
    /// Иначе вопрос уйдёт напрямую и вернётся тот же придушенный кэш —
    /// вся затея потеряет смысл.
    /// </summary>
    public static List<Ipv4Net> ServerNets() => Servers
        .Select(Cidr.Parse)
        .Where(net => net is not null)
        .Select(net => net!.Value)
        .ToList();

    /// <summary>Как список серверов записывается в правило.</summary>
    public static string ServerList() => string.Join(";", Servers);
}
