using System.Linq;
using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Параметры маскировки AmneziaWG: все до единого доходят до службы.
///
/// Здесь проверяется то, из-за чего Windows не подключался вовсе.
/// Приложение читало из ключа только часть параметров, а остальные молча
/// выбрасывало. Маскировка работает лишь целиком: потеряли защиту
/// заголовков — и сервер перестал узнавать наши пакеты. Отправка идёт,
/// в ответ ничего, окно вечно показывает «подключение».
///
/// На Mac те же ключи работали: там список был полный. Поэтому здесь
/// проверяется каждый параметр по отдельности.
/// </summary>
public class AmneziaMaskingTests
{
    /// <summary>Ключ, в котором есть всё, что умеет AmneziaWG.</summary>
    private const string Полный = """
        [Interface]
        PrivateKey = aG9tZWhvbWVob21laG9tZWhvbWVob21laG9tZWhvbWU=
        Address = 10.8.0.2/32
        DNS = 1.1.1.1, 1.0.0.1
        MTU = 1420
        Jc = 4
        Jmin = 40
        Jmax = 70
        S1 = 15
        S2 = 30
        S3 = 51
        S4 = 62
        H1 = 1148536553
        H2 = 1854197995
        H3 = 1394339776
        H4 = 1449049522
        I1 = <b 0xf6249187>
        I2 = <b 0x4a1c>
        I3 = <b 0x8801>
        I4 = <b 0x1f2e>
        I5 = <b 0x9a44>
        HeaderProtectionKey = aGVhZGVyaGVhZGVyaGVhZGVyaGVhZGVyaGVhZGVyMTI=
        ContentPaddingAddition = 32
        RekeyAfterTime = 120
        RekeyTimeout = 5
        RejectAfterTime = 180
        KeepaliveTimeout = 10
        MaxHandshakeAttempts = 18
        RandomTrailers = 1
        DisableCookies = 1

        [Peer]
        PublicKey = c2VydmVyc2VydmVyc2VydmVyc2VydmVyc2VydmVyMTI=
        Endpoint = 91.201.0.1:51820
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 25
        """;

    /// <summary>
    /// Всё, что понимает служба туннеля.
    ///
    /// Список взят из разбора настроек в библиотеке amneziawg-windows —
    /// той самой, на которой работает служба. При сборке он ещё раз
    /// сверяется с её исходниками.
    /// </summary>
    public static TheoryData<string> ПараметрыСлужбы => new()
    {
        "jc", "jmin", "jmax",
        "s1", "s2", "s3", "s4",
        "h1", "h2", "h3", "h4",
        "i1", "i2", "i3", "i4", "i5",
        "headerprotectionkey", "contentpaddingaddition",
        "rekeyaftertime", "rekeytimeout", "rejectaftertime",
        "keepalivetimeout", "maxhandshakeattempts",
        "randomtrailers", "disablecookies",
    };

    [Theory]
    [MemberData(nameof(ПараметрыСлужбы))]
    public void ПриложениеЗнаетКаждыйПараметрСлужбы(string параметр)
    {
        Assert.Contains(параметр, WgProfile.AmneziaKeys);
    }

    [Fact]
    public void ВсеПараметрыИзКлючаДоходятДоСлужбы()
    {
        var profile = WgProfile.Parse(Полный);
        var text = profile.ToConfigText(["0.0.0.0/0"], includeDns: false);

        foreach (var имя in new[]
                 {
                     "Jc", "Jmin", "Jmax", "S1", "S2", "S3", "S4",
                     "H1", "H2", "H3", "H4",
                     "I1", "I2", "I3", "I4", "I5",
                     "HeaderProtectionKey", "ContentPaddingAddition",
                     "RekeyAfterTime", "RekeyTimeout", "RejectAfterTime",
                     "KeepaliveTimeout", "MaxHandshakeAttempts",
                     "RandomTrailers", "DisableCookies",
                 })
        {
            Assert.Contains($"{имя} = ", text);
        }
    }

    [Fact]
    public void ЗащитаЗаголовковНеТеряется()
    {
        // Отдельная проверка: именно из-за этого параметра Windows
        // не подключался. Сервер применяет защиту заголовков, а клиент,
        // не получив ключа, шлёт пакеты, которых сервер не узнаёт.
        var profile = WgProfile.Parse(Полный);

        Assert.True(profile.AmneziaParams.ContainsKey("headerprotectionkey"),
            "Ключ защиты заголовков потерялся при чтении — сервер не ответит");

        Assert.Contains("HeaderProtectionKey = aGVhZGVyaGVhZGVyaGVhZGVyaGVhZGVyaGVhZGVyMTI=",
            profile.ToConfigText(["0.0.0.0/0"], includeDns: false));
    }

    [Fact]
    public void ЧислоПараметровСовпадаетСоСлужбой()
    {
        Assert.Equal(ПараметрыСлужбы.Count, WgProfile.AmneziaKeys.Count);
    }

    [Fact]
    public void ПараметровМаскировкиРовноСтолькоСколькоВКлюче()
    {
        // В ключе их 25 — ни один не должен пропасть по дороге.
        var profile = WgProfile.Parse(Полный);

        Assert.True(profile.IsAmnezia);
        Assert.Equal(25, profile.AmneziaParams.Count);
        Assert.Equal("AmneziaWG", profile.ProtocolName);
    }

    [Fact]
    public void ОбычныйКлючБезМаскировкиОстаётсяОбычным()
    {
        var profile = WgProfile.Parse("""
            [Interface]
            PrivateKey = aG9tZWhvbWVob21laG9tZWhvbWVob21laG9tZWhvbWU=
            Address = 10.8.0.2/32

            [Peer]
            PublicKey = c2VydmVyc2VydmVyc2VydmVyc2VydmVyc2VydmVyMTI=
            Endpoint = 91.201.0.1:51820
            AllowedIPs = 0.0.0.0/0
            """);

        Assert.False(profile.IsAmnezia);
        Assert.Equal("WireGuard", profile.ProtocolName);
    }
}
