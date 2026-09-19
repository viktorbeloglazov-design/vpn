using System;
using System.Collections.Generic;
using System.Linq;

namespace QPVPN.Core;

/// <summary>Подсеть IPv4: начало и длина префикса.</summary>
public readonly record struct Ipv4Net(uint Start, int Prefix)
{
    public long Size => 1L << (32 - Prefix);
    public long EndInclusive => Start + Size - 1;

    public override string ToString()
    {
        var a = (Start >> 24) & 0xFF;
        var b = (Start >> 16) & 0xFF;
        var c = (Start >> 8) & 0xFF;
        var d = Start & 0xFF;
        return $"{a}.{b}.{c}.{d}/{Prefix}";
    }
}

/// <summary>
/// Разбор адресов и арифметика подсетей.
///
/// Туннелю задаётся список того, что в него заходит. Поэтому режим
/// «всё кроме правил» считается как дополнение — всё адресное пространство
/// минус исключённые подсети.
/// </summary>
public static class Cidr
{
    public static uint? ParseAddress(string value)
    {
        var parts = value.Trim().Split('.');
        if (parts.Length != 4) return null;

        uint result = 0;
        foreach (var part in parts)
        {
            if (part.Length == 0 || part.Length > 3 || !part.All(char.IsDigit)) return null;
            if (part.Length > 1 && part[0] == '0') return null;
            var number = int.Parse(part);
            if (number > 255) return null;
            result = (result << 8) | (uint)number;
        }
        return result;
    }

    /// <summary>Принимает «10.0.0.0/8» и одиночный «1.2.3.4» (станет /32).</summary>
    public static Ipv4Net? Parse(string value)
    {
        var text = value.Trim();
        var slash = text.IndexOf('/');
        if (slash < 0)
        {
            var single = ParseAddress(text);
            return single is null ? null : new Ipv4Net(single.Value, 32);
        }

        var address = ParseAddress(text[..slash]);
        if (address is null) return null;
        if (!int.TryParse(text[(slash + 1)..], out var prefix)) return null;
        if (prefix < 0 || prefix > 32) return null;

        var mask = prefix == 0 ? 0u : ~((1u << (32 - prefix)) - 1);
        return new Ipv4Net(address.Value & mask, prefix);
    }

    public static bool IsDomain(string value)
    {
        var text = value.Trim().ToLowerInvariant();
        if (text.Length == 0 || text.Length > 253 || !text.Contains('.')) return false;
        if (text.StartsWith('.') || text.EndsWith('.') || text.Contains("..")) return false;
        if (!text.All(c => (char.IsLetterOrDigit(c) && c < 128) || c == '.' || c == '-')) return false;
        return text.Split('.').All(label =>
            label.Length is > 0 and <= 63 && !label.StartsWith('-') && !label.EndsWith('-'));
    }

    /// <summary>Схлопывает пересекающиеся и соседние подсети.</summary>
    public static List<Ipv4Net> Merge(IEnumerable<Ipv4Net> nets)
    {
        var ranges = nets.Select(net => (Start: (long)net.Start, End: net.EndInclusive))
            .OrderBy(range => range.Start)
            .ToList();
        if (ranges.Count == 0) return new List<Ipv4Net>();

        var merged = new List<(long Start, long End)>();
        foreach (var range in ranges)
        {
            if (merged.Count > 0 && range.Start <= merged[^1].End + 1)
            {
                merged[^1] = (merged[^1].Start, Math.Max(merged[^1].End, range.End));
            }
            else
            {
                merged.Add(range);
            }
        }
        return merged.SelectMany(range => RangeToNets(range.Start, range.End)).ToList();
    }

    /// <summary>Всё адресное пространство минус перечисленные подсети.</summary>
    public static List<Ipv4Net> Complement(IEnumerable<Ipv4Net> excluded)
    {
        var ranges = excluded.Select(net => (Start: (long)net.Start, End: net.EndInclusive))
            .OrderBy(range => range.Start)
            .ToList();
        if (ranges.Count == 0) return new List<Ipv4Net> { new(0, 0) };

        var merged = new List<(long Start, long End)>();
        foreach (var range in ranges)
        {
            if (merged.Count > 0 && range.Start <= merged[^1].End + 1)
            {
                merged[^1] = (merged[^1].Start, Math.Max(merged[^1].End, range.End));
            }
            else
            {
                merged.Add(range);
            }
        }

        var result = new List<Ipv4Net>();
        long cursor = 0;
        foreach (var (start, end) in merged)
        {
            if (start > cursor) result.AddRange(RangeToNets(cursor, start - 1));
            cursor = Math.Max(cursor, end + 1);
            if (cursor > 0xFFFFFFFFL) break;
        }
        if (cursor <= 0xFFFFFFFFL) result.AddRange(RangeToNets(cursor, 0xFFFFFFFFL));
        return result;
    }

    /// <summary>Наименьший набор подсетей, покрывающий диапазон целиком.</summary>
    public static List<Ipv4Net> RangeToNets(long start, long endInclusive)
    {
        var result = new List<Ipv4Net>();
        var current = start;
        while (current <= endInclusive)
        {
            var prefix = 32;
            while (prefix > 0)
            {
                var candidate = prefix - 1;
                var size = 1L << (32 - candidate);
                if (current % size != 0 || current + size - 1 > endInclusive) break;
                prefix = candidate;
            }
            result.Add(new Ipv4Net((uint)current, prefix));
            current += 1L << (32 - prefix);
        }
        return result;
    }
}
