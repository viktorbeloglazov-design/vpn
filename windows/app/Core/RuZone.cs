using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace QPVPN.Core;

/// <summary>
/// Адресное пространство России, вшитое в приложение.
///
/// Нужно для режима «всё через VPN, кроме российской зоны»: из туннеля
/// вычитаются все выданные России подсети, и российские сайты открываются
/// с домашнего адреса без единого правила.
/// </summary>
public static class RuZone
{
    private static List<Ipv4Net>? _cache;

    public static IReadOnlyList<Ipv4Net> Networks()
    {
        if (_cache is not null) return _cache;

        var nets = new List<Ipv4Net>(9000);
        using var stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("QPVPN.Assets.ru_ipv4.txt");
        if (stream is not null)
        {
            using var reader = new StreamReader(stream);
            while (reader.ReadLine() is { } line)
            {
                var text = line.Trim();
                if (text.Length == 0 || text.StartsWith('#')) continue;
                if (Cidr.Parse(text) is { } net) nets.Add(net);
            }
        }

        _cache = nets;
        return _cache;
    }

    public static int Count => Networks().Count;
}
