using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace QPVPN.Core;

/// <summary>
/// Память адресов сервисов.
///
/// ChatGPT живёт на Cloudflare и отвечает с адресов, которые время от
/// времени меняются. Если помнить только сегодняшний ответ DNS, то после
/// смены адреса сайт перестанет открываться до следующего подключения.
/// Поэтому адреса накапливаются: увиденное однажды помнится месяц, а
/// потом забывается, чтобы список не разрастался чужими адресами.
/// </summary>
public sealed class KnownAddresses
{
    public sealed record Entry(string Address, DateTimeOffset SeenAt);

    /// <summary>Сколько помнится адрес, который больше не встречается.</summary>
    public static readonly TimeSpan Life = TimeSpan.FromDays(30);

    /// <summary>
    /// Сколько адресов помним всего.
    ///
    /// Ограничение на случай, если сервис начнёт отвечать с нового адреса
    /// на каждый запрос: сотня адресов — это маршруты, а не бесконечность.
    /// </summary>
    public const int Limit = 400;

    public static string Path => System.IO.Path.Combine(Store.SettingsDirectory, "addresses.json");

    /// <summary>
    /// Складывает свежий ответ DNS с тем, что помним.
    ///
    /// Свежие адреса получают сегодняшнюю дату, старые сохраняют свою.
    /// Забытым считается адрес, который не встречался дольше месяца.
    /// </summary>
    public static List<Entry> Merge(IEnumerable<Entry> stored, IEnumerable<string> fresh, DateTimeOffset now)
    {
        var result = new Dictionary<string, Entry>(StringComparer.OrdinalIgnoreCase);

        foreach (var entry in stored)
        {
            if (now - entry.SeenAt > Life) continue;
            if (Cidr.Parse(entry.Address) is null) continue;
            result[entry.Address] = entry;
        }

        foreach (var address in fresh)
        {
            if (Cidr.Parse(address) is null) continue;
            result[address] = new Entry(address, now);
        }

        // Если адресов набралось больше разумного, расстаёмся с самыми
        // давними: свежие нужнее.
        return result.Values
            .OrderByDescending(entry => entry.SeenAt)
            .Take(Limit)
            .ToList();
    }

    /// <summary>Читает память адресов с диска.</summary>
    public static List<Entry> Load()
    {
        try
        {
            if (!File.Exists(Path)) return new List<Entry>();
            return JsonSerializer.Deserialize<List<Entry>>(File.ReadAllText(Path))
                   ?? new List<Entry>();
        }
        catch (Exception)
        {
            return new List<Entry>();
        }
    }

    /// <summary>Записывает память адресов на диск.</summary>
    public static void Save(IEnumerable<Entry> entries)
    {
        try
        {
            Directory.CreateDirectory(Store.SettingsDirectory);
            File.WriteAllText(Path, JsonSerializer.Serialize(entries));
        }
        catch (Exception)
        {
            // Память не легла на диск — в этот раз обойдёмся свежим ответом.
        }
    }

    /// <summary>Адреса из памяти как подсети из одного адреса.</summary>
    public static List<Ipv4Net> Nets(IEnumerable<Entry> entries) => entries
        .Select(entry => Cidr.Parse(entry.Address))
        .Where(net => net is not null)
        .Select(net => net!.Value)
        .ToList();
}
