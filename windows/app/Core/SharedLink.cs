using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;

namespace QPVPN.Core;

/// <summary>
/// Разбор того, чем делится Amnezia: ссылка vpn:// и QR-код с ней же.
///
/// Внутри — сжатый свёрток с настройками, где лежит обычный текст
/// конфигурации WireGuard или AmneziaWG.
/// </summary>
public static class SharedLink
{
    private const string Marker = "[Interface]";

    public static bool LooksLikeLink(string input)
    {
        var text = input.Trim().ToLowerInvariant();
        return text.StartsWith("vpn://") || text.StartsWith("amnezia://");
    }

    /// <summary>Достаёт текст конфигурации из чего угодно, чем поделились.</summary>
    public static string? ExtractConfig(string input)
    {
        var text = input.Trim();
        if (text.Length == 0) return null;
        if (text.Contains(Marker)) return CleanUp(text);

        var payload = text;
        foreach (var prefix in new[] { "vpn://", "VPN://", "amnezia://" })
        {
            if (payload.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                payload = payload[prefix.Length..];
                break;
            }
        }
        payload = payload.Trim();

        var bytes = DecodeBase64(payload);
        if (bytes is null) return null;

        // Qt кладёт впереди четыре байта с исходным размером, дальше zlib.
        foreach (var skip in new[] { 4, 6, 0, 2 })
        {
            if (bytes.Length <= skip) continue;
            var unpacked = Inflate(bytes.AsSpan(skip).ToArray(), skip is 4 or 0);
            if (unpacked is null) continue;
            var config = FromText(unpacked);
            if (config is not null) return config;
        }

        var plain = Encoding.UTF8.GetString(bytes);
        return FromText(plain);
    }

    /// <summary>
    /// В свёртке настройки лежат строкой внутри JSON, и структура от версии
    /// к версии меняется. Поэтому ищем не имена полей, а саму конфигурацию.
    /// </summary>
    private static string? FromText(string text)
    {
        var start = text.IndexOf(Marker, StringComparison.Ordinal);
        if (start < 0) return null;
        if (!text.Contains('"')) return CleanUp(text);

        var quoteBefore = text.LastIndexOf('"', start);
        if (quoteBefore < 0) return CleanUp(text);

        var quoteAfter = ClosingQuote(text, start);
        if (quoteAfter < 0) return CleanUp(text);

        return CleanUp(UnescapeJson(text[(quoteBefore + 1)..quoteAfter]));
    }

    private static int ClosingQuote(string text, int from)
    {
        for (var index = from; index < text.Length; index++)
        {
            if (text[index] == '"' && (index == 0 || text[index - 1] != '\\')) return index;
        }
        return -1;
    }

    private static string UnescapeJson(string value) => value
        .Replace("\\r\\n", "\n")
        .Replace("\\n", "\n")
        .Replace("\\r", "\n")
        .Replace("\\t", "\t")
        .Replace("\\\"", "\"")
        .Replace("\\\\", "\\");

    /// <summary>Обрезает всё, что оказалось до и после самой конфигурации.</summary>
    private static string CleanUp(string text)
    {
        var start = text.IndexOf(Marker, StringComparison.Ordinal);
        if (start < 0) return text.Trim();

        var lines = text[start..]
            .Replace("\r\n", "\n")
            .Split('\n')
            .TakeWhile(line =>
            {
                var trimmed = line.Trim();
                return trimmed.Length == 0 || trimmed.StartsWith('[') || trimmed.StartsWith('#') || trimmed.Contains('=');
            });
        return string.Join("\n", lines).Trim();
    }

    private static byte[]? DecodeBase64(string value)
    {
        var normalized = new string(value.Replace('-', '+').Replace('_', '/')
            .Where(c => !char.IsWhiteSpace(c)).ToArray());
        normalized = (normalized.Length % 4) switch
        {
            2 => normalized + "==",
            3 => normalized + "=",
            0 => normalized,
            _ => "",
        };
        if (normalized.Length == 0) return null;

        try
        {
            return Convert.FromBase64String(normalized);
        }
        catch (FormatException)
        {
            return null;
        }
    }

    /// <summary>Распаковка: сначала как поток zlib, потом как голый deflate.</summary>
    private static string? Inflate(byte[] data, bool withHeader)
    {
        foreach (var zlib in withHeader ? new[] { true, false } : new[] { false, true })
        {
            try
            {
                using var source = new MemoryStream(data);
                using Stream decoder = zlib
                    ? new ZLibStream(source, CompressionMode.Decompress)
                    : new DeflateStream(source, CompressionMode.Decompress);
                using var target = new MemoryStream();
                decoder.CopyTo(target, 64 * 1024);
                if (target.Length == 0) continue;
                return Encoding.UTF8.GetString(target.ToArray());
            }
            catch (Exception)
            {
                // Пробуем следующий способ распаковки.
            }
        }
        return null;
    }
}
