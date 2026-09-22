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

        var nets = Read();

        // Пустоту не запоминаем. Без этого списка через VPN идёт всё, включая
        // Ozon, банки и госуслуги, — они видят казахстанский адрес и просто
        // не открываются. Один неудачный заход не должен означать, что так
        // будет до перезапуска программы.
        if (nets.Count > 0) _cache = nets;
        return nets;
    }

    private static List<Ipv4Net> Read()
    {
        var nets = new List<Ipv4Net>(9000);
        var assembly = Assembly.GetExecutingAssembly();

        // Ищем по концу имени, а не по точному совпадению: полное имя
        // встроенного файла складывается из настроек проекта, и достаточно
        // переименовать папку, чтобы оно перестало совпадать. Молча, без
        // единой ошибки — просто пустой список и весь трафик в туннель.
        var name = Array.Find(assembly.GetManifestResourceNames(),
            item => item.EndsWith("ru_ipv4.txt", StringComparison.OrdinalIgnoreCase));
        if (name is null) return nets;

        using var stream = assembly.GetManifestResourceStream(name);
        if (stream is null) return nets;

        using var reader = new StreamReader(stream);
        while (reader.ReadLine() is { } line)
        {
            var text = line.Trim();
            if (text.Length == 0 || text.StartsWith('#')) continue;
            if (Cidr.Parse(text) is { } net) nets.Add(net);
        }
        return nets;
    }

    public static int Count => Networks().Count;
}
