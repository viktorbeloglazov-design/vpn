using System.Collections.Generic;
using System.Linq;

namespace QPVPN.Core;

/// <summary>
/// Российская зона, ужатая до числа маршрутов, которое система принимает.
///
/// Точный список даёт больше двадцати тысяч маршрутов — столько Windows
/// прокладывает заметными секундами. Список укрупняется: соседние подсети
/// сливаются, прощая небольшие промежутки между ними. Платой за это идут
/// чужие адреса, попавшие в промежутки, — те из них, на которых живут
/// заблокированные сервисы, возвращаются в туннель поимённо.
///
/// Вынесено отдельно от подключения, чтобы результат можно было проверить:
/// ошибка здесь означает, что российский сайт уходит через VPN
/// и не открывается.
/// </summary>
public static class RuZonePlan
{
    /// <summary>Столько маршрутов система принимает спокойно.</summary>
    public const int DefaultMaxRoutes = 4_000;

    /// <summary>Шаги укрупнения: какой промежуток между подсетями прощаем.</summary>
    public static readonly long[] DefaultGaps = { 4_096, 16_384, 65_536, 262_144, 1_048_576 };

    /// <summary>
    /// Считает зону обхода: что пойдёт мимо туннеля.
    /// </summary>
    /// <param name="exact">Точный список выданных России подсетей.</param>
    /// <param name="keep">Подсети, которые обязаны остаться в туннеле.</param>
    public static List<Ipv4Net> Fit(
        IReadOnlyList<Ipv4Net> exact,
        IReadOnlyList<Ipv4Net> keep,
        int maxRoutes = DefaultMaxRoutes,
        long[]? gaps = null)
    {
        if (exact.Count == 0) return new List<Ipv4Net>();

        gaps ??= DefaultGaps;
        var zone = Cidr.Subtract(exact.ToList(), keep.ToList());
        var routes = Cidr.Complement(zone).Count;

        foreach (var gap in gaps)
        {
            if (routes <= maxRoutes) break;
            zone = Cidr.Subtract(Cidr.MergeWithGap(exact.ToList(), gap), keep.ToList());
            routes = Cidr.Complement(zone).Count;
        }
        return zone;
    }

    /// <summary>Сколько маршрутов получится из этой зоны.</summary>
    public static int RouteCount(IReadOnlyList<Ipv4Net> zone) =>
        zone.Count == 0 ? 1 : Cidr.Complement(zone.ToList()).Count;
}
