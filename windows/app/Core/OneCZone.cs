using System;
using System.Collections.Generic;
using System.Linq;

namespace QPVPN.Core;

/// <summary>
/// Рабочая зона для 1С.
///
/// Адреса сервера 1С заложены в программу. Они идут через VPN всегда:
/// без доступа к 1С работать нельзя, и выбирать тут нечего.
/// </summary>
public static class OneCZone
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
        new("1С", "https://135.106.142.73/Ka"),
        new("1С, прошлая база", "https://135.106.142.73/Ka_old"),
    };

    public static IReadOnlyList<string> Hosts =>
        Resources.Select(resource => resource.Host).Distinct().ToList();

    public static int Count => Resources.Count;
}
