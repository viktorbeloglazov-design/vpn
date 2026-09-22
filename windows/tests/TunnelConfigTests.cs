using System.Collections.Generic;
using System.Linq;
using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Файл настроек, который читает служба туннеля.
///
/// Если в нём потеряется хоть один параметр маскировки, сервер AmneziaWG
/// просто не ответит: отправка будет идти, приёма не будет, и адрес
/// не определится. Со стороны это выглядит как «ничего не работает».
/// </summary>
public class TunnelConfigTests
{
    private const string Sample = """
        [Interface]
        PrivateKey = aG9tZWhvbWVob21laG9tZWhvbWVob21laG9tZWhvbWU=
        Address = 10.8.0.2/32
        DNS = 10.8.0.1
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

        [Peer]
        PublicKey = c2VydmVyc2VydmVyc2VydmVyc2VydmVyc2VydmVyMTI=
        PresharedKey = cHJlc2hhcmVkcHJlc2hhcmVkcHJlc2hhcmVkcHJlcw=
        Endpoint = 91.201.0.1:51820
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 25
        """;

    private static WgProfile Parsed() => WgProfile.Parse(Sample);

    [Fact]
    public void ПараметрыМаскировкиДоезжаютДоФайла()
    {
        var text = Parsed().ToConfigText(["0.0.0.0/0"], includeDns: true);

        // Каждый из них сервер проверяет. Пропал один — ответа не будет.
        foreach (var name in new[] { "Jc", "Jmin", "Jmax", "S1", "S2", "S3", "S4",
                                     "H1", "H2", "H3", "H4", "I1", "I2" })
        {
            Assert.Contains($"{name} = ", text);
        }
    }

    [Fact]
    public void ЗначенияМаскировкиНеПеремешаны()
    {
        var text = Parsed().ToConfigText(["0.0.0.0/0"], includeDns: true);

        Assert.Contains("Jc = 4", text);
        Assert.Contains("Jmin = 40", text);
        Assert.Contains("H1 = 1148536553", text);
        Assert.Contains("H4 = 1449049522", text);
        Assert.Contains("I1 = <b 0xf6249187>", text);
    }

    [Fact]
    public void ЭтоПрофильAmnezia()
    {
        Assert.True(Parsed().IsAmnezia);
        Assert.Equal("AmneziaWG", Parsed().ProtocolName);
    }

    [Fact]
    public void КлючиИАдресСервераНаМесте()
    {
        var text = Parsed().ToConfigText(["0.0.0.0/0"], includeDns: true);

        Assert.Contains("PrivateKey = aG9tZ", text);
        Assert.Contains("PublicKey = c2VydmVy", text);
        Assert.Contains("PresharedKey = cHJlc2", text);
        Assert.Contains("Endpoint = 91.201.0.1:51820", text);
        Assert.Contains("PersistentKeepalive = 25", text);
    }

    [Fact]
    public void МаршрутыПопадаютВФайлЦеликом()
    {
        var routes = new[] { "1.0.0.0/8", "2.0.0.0/8", "3.0.0.0/8" };
        var text = Parsed().ToConfigText(routes, includeDns: true);

        var line = text.Split('\n').Single(l => l.StartsWith("AllowedIPs"));
        foreach (var route in routes) Assert.Contains(route, line);
    }

    [Fact]
    public void РазмерПакетаМожноЗадатьПоверхКлюча()
    {
        var text = Parsed().ToConfigText(["0.0.0.0/0"], includeDns: true, mtuOverride: 1280);

        Assert.Contains("MTU = 1280", text);
        Assert.DoesNotContain("MTU = 1420", text);
    }

    [Fact]
    public void БезПереопределенияБерётсяРазмерИзКлюча()
    {
        var text = Parsed().ToConfigText(["0.0.0.0/0"], includeDns: true);

        Assert.Contains("MTU = 1420", text);
    }

    [Fact]
    public void СменаВходаНеТрогаетКлючи()
    {
        var profile = Parsed();
        var moved = profile with { Endpoint = "95.213.0.1:31984" };
        var text = moved.ToConfigText(["0.0.0.0/0"], includeDns: true);

        Assert.Contains("Endpoint = 95.213.0.1:31984", text);
        // Узел-пересыльщик ничего не расшифровывает: ключи те же самые.
        Assert.Equal(profile.PrivateKey, moved.PrivateKey);
        Assert.Equal(profile.PublicKey, moved.PublicKey);
        Assert.Contains("PresharedKey = cHJlc2", text);
    }

    [Fact]
    public void АдресВТуннелеСохраняется()
    {
        var text = Parsed().ToConfigText(["0.0.0.0/0"], includeDns: true);

        // Без него служба не назначит адаптеру адрес — ответы будет некуда
        // принимать.
        Assert.Contains("Address = 10.8.0.2/32", text);
    }

    [Fact]
    public void БезDnsСтрокиНет()
    {
        var text = Parsed().ToConfigText(["0.0.0.0/0"], includeDns: false);

        Assert.DoesNotContain("DNS = ", text);
    }

    [Fact]
    public void РазделыИдутВПравильномПорядке()
    {
        var text = Parsed().ToConfigText(["0.0.0.0/0"], includeDns: true);

        var iface = text.IndexOf("[Interface]");
        var peer = text.IndexOf("[Peer]");
        Assert.True(iface >= 0 && peer > iface,
            "служба читает файл сверху вниз: [Interface] должен быть первым");
    }

    [Fact]
    public void ИмяУзлаОтделяетсяОтПорта()
    {
        Assert.Equal("91.201.0.1", Parsed().EndpointHost);
    }
}
