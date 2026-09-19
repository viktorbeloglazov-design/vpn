using System;
using System.Collections.Generic;
using System.Linq;

namespace QPVPN.Core;

/// <summary>
/// Второй переключатель: рабочие ресурсы.
///
/// Адреса заложены в приложение. Включён — они идут через VPN, выключен —
/// напрямую. Списки те же, что в версии для Android.
/// </summary>
public static class WorkFilter
{
    public sealed record Resource(string Title, string Url)
    {
        /// <summary>Узел из ссылки: без схемы, пути и порта.</summary>
        public string Host
        {
            get
            {
                var text = Url;
                var scheme = text.IndexOf("://", StringComparison.Ordinal);
                if (scheme >= 0) text = text[(scheme + 3)..];
                var slash = text.IndexOf('/');
                if (slash >= 0) text = text[..slash];
                var colon = text.IndexOf(':');
                if (colon >= 0) text = text[..colon];
                return text;
            }
        }
    }

    public static readonly IReadOnlyList<Resource> Resources = new List<Resource>
    {
        new("Ka", "https://135.106.142.73/Ka"),
        new("Ka_old", "https://135.106.142.73/Ka_old"),
    };

    public static IReadOnlyList<string> Hosts =>
        Resources.Select(resource => resource.Host).Distinct().ToList();

    public static int Count => Resources.Count;
}
