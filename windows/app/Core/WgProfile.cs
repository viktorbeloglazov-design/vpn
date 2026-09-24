using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace QPVPN.Core;

/// <summary>
/// Разобранный профиль WireGuard или AmneziaWG.
///
/// Запись, а не класс: нужно уметь делать копию с другим адресом входа —
/// когда до сервера напрямую не достучаться и в дело идёт запасной узел.
/// </summary>
public sealed record WgProfile
{
    /// <summary>Имена параметров маскировки так, как их ждёт библиотека AmneziaWG.</summary>
    /// <summary>
    /// Параметры маскировки AmneziaWG, которые надо донести до службы.
    ///
    /// Здесь должно быть ровно то, что понимает служба туннеля. Чего в этом
    /// списке нет, то при чтении ключа молча выбрасывается и до службы не
    /// доезжает, — а маскировка работает только целиком. Стоит потерять
    /// хотя бы HeaderProtectionKey, и сервер перестаёт узнавать наши
    /// пакеты: приложение показывает «подключение», отправка идёт,
    /// в ответ не приходит ничего. Именно так туннель и висел на Windows,
    /// пока здесь лежали одни только Jc, S, H и I.
    ///
    /// Список сверяется с исходниками службы при каждой проверке (шаг
    /// «Параметры маскировки»): если Amnezia добавит новый параметр или
    /// перестанет понимать старый, об этом скажет сборка, а не человек,
    /// у которого перестал работать VPN.
    /// </summary>
    private static readonly (string Key, string Name)[] AmneziaFields =
    {
        // Мусорные пакеты перед рукопожатием.
        ("jc", "Jc"), ("jmin", "Jmin"), ("jmax", "Jmax"),

        // Подмена размеров и заголовков служебных пакетов.
        ("s1", "S1"), ("s2", "S2"), ("s3", "S3"), ("s4", "S4"),
        ("h1", "H1"), ("h2", "H2"), ("h3", "H3"), ("h4", "H4"),

        // Особые пакеты рукопожатия.
        ("i1", "I1"), ("i2", "I2"), ("i3", "I3"), ("i4", "I4"), ("i5", "I5"),

        // Защита заголовков и набивка — без них сервер не узнаёт пакеты.
        ("headerprotectionkey", "HeaderProtectionKey"),
        ("contentpaddingaddition", "ContentPaddingAddition"),

        // Сроки жизни сессии: сервер и клиент должны считать их одинаково.
        ("rekeyaftertime", "RekeyAfterTime"),
        ("rekeytimeout", "RekeyTimeout"),
        ("rejectaftertime", "RejectAfterTime"),
        ("keepalivetimeout", "KeepaliveTimeout"),
        ("maxhandshakeattempts", "MaxHandshakeAttempts"),
        ("randomtrailers", "RandomTrailers"),
        ("disablecookies", "DisableCookies"),
    };

    /// <summary>Имена параметров маскировки, как их читают из ключа.</summary>
    public static IReadOnlyList<string> AmneziaKeys =>
        AmneziaFields.Select(item => item.Key).ToList();

    public string PrivateKey { get; init; } = "";
    public List<string> Addresses { get; init; } = new();
    public List<string> Dns { get; init; } = new();
    public int Mtu { get; init; } = 1420;
    public string PublicKey { get; init; } = "";
    public string PresharedKey { get; init; } = "";
    public string Endpoint { get; init; } = "";
    public int Keepalive { get; init; } = 25;

    /// <summary>Параметры маскировки AmneziaWG, если они были в файле.</summary>
    public Dictionary<string, string> AmneziaParams { get; init; } = new();

    public bool IsAmnezia => AmneziaParams.Count > 0;
    public string ProtocolName => IsAmnezia ? "AmneziaWG" : "WireGuard";
    public bool HasIpv6Address => Addresses.Any(address => address.Contains(':'));

    public string EndpointHost
    {
        get
        {
            var colon = Endpoint.LastIndexOf(':');
            return colon > 0 ? Endpoint[..colon] : Endpoint;
        }
    }

    public sealed class ParseException : Exception
    {
        public ParseException(string message) : base(message) { }
    }

    /// <summary>
    /// Собирает текст конфигурации для службы туннеля.
    ///
    /// AllowedIPs здесь — главное: именно этот список решает, что пойдёт
    /// в туннель.
    /// </summary>
    /// <param name="mtuOverride">Размер пакета вместо записанного в ключе; 0 — из ключа.</param>
    public string ToConfigText(IEnumerable<string> allowedIps, bool includeDns, int mtuOverride = 0)
    {
        var builder = new StringBuilder();
        builder.AppendLine("[Interface]");
        builder.AppendLine($"PrivateKey = {PrivateKey}");
        builder.AppendLine($"Address = {string.Join(", ", Addresses)}");
        builder.AppendLine($"MTU = {(mtuOverride > 0 ? mtuOverride : Mtu)}");
        if (includeDns && Dns.Count > 0)
        {
            builder.AppendLine($"DNS = {string.Join(", ", Dns)}");
        }

        // Параметры маскировки: без них сервер Amnezia не ответит.
        foreach (var (key, name) in AmneziaFields)
        {
            if (AmneziaParams.TryGetValue(key, out var value))
            {
                builder.AppendLine($"{name} = {value}");
            }
        }

        builder.AppendLine();
        builder.AppendLine("[Peer]");
        builder.AppendLine($"PublicKey = {PublicKey}");
        if (PresharedKey.Length > 0)
        {
            builder.AppendLine($"PresharedKey = {PresharedKey}");
        }
        builder.AppendLine($"Endpoint = {Endpoint}");
        builder.AppendLine($"AllowedIPs = {string.Join(", ", allowedIps)}");
        if (Keepalive > 0)
        {
            builder.AppendLine($"PersistentKeepalive = {Keepalive}");
        }
        return builder.ToString();
    }

    public static WgProfile Parse(string text)
    {
        var section = "";
        var iface = new Dictionary<string, string>();
        var peer = new Dictionary<string, string>();

        foreach (var rawLine in text.Replace("\r\n", "\n").Split('\n'))
        {
            var line = rawLine;
            var hash = line.IndexOf('#');
            if (hash >= 0) line = line[..hash];
            line = line.Trim();
            if (line.Length == 0) continue;

            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                section = line[1..^1].Trim().ToLowerInvariant();
                continue;
            }

            var equals = line.IndexOf('=');
            if (equals < 0) continue;
            var key = line[..equals].Trim().ToLowerInvariant();
            var value = line[(equals + 1)..].Trim();

            if (section == "interface") iface[key] = value;
            else if (section == "peer") peer[key] = value;
        }

        if (iface.Count == 0) throw new ParseException("В настройках нет раздела [Interface].");
        if (peer.Count == 0) throw new ParseException("В настройках нет раздела [Peer].");

        var privateKey = iface.GetValueOrDefault("privatekey", "");
        if (privateKey.Length == 0) throw new ParseException("В настройках нет приватного ключа.");

        var publicKey = peer.GetValueOrDefault("publickey", "");
        if (publicKey.Length == 0) throw new ParseException("В настройках нет публичного ключа сервера.");

        var endpoint = peer.GetValueOrDefault("endpoint", "");
        if (endpoint.Length == 0) throw new ParseException("В настройках нет адреса сервера (Endpoint).");

        var amnezia = new Dictionary<string, string>();
        foreach (var (key, _) in AmneziaFields)
        {
            if (iface.TryGetValue(key, out var value) && value.Length > 0) amnezia[key] = value;
        }

        return new WgProfile
        {
            PrivateKey = privateKey,
            Addresses = SplitList(iface.GetValueOrDefault("address", "")),
            Dns = SplitList(iface.GetValueOrDefault("dns", "")),
            Mtu = int.TryParse(iface.GetValueOrDefault("mtu", ""), out var mtu) ? mtu : 1420,
            PublicKey = publicKey,
            PresharedKey = peer.GetValueOrDefault("presharedkey", ""),
            Endpoint = endpoint,
            Keepalive = int.TryParse(peer.GetValueOrDefault("persistentkeepalive", ""), out var keepalive) ? keepalive : 25,
            AmneziaParams = amnezia,
        };
    }

    private static List<string> SplitList(string value) => value
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .ToList();
}
