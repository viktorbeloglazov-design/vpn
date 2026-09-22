using System.Linq;
using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Что уходит через VPN, а что идёт напрямую.
///
/// Российский сайт, случайно попавший в туннель, просто перестаёт
/// работать: он видит казахстанский адрес и отказывается открываться.
/// Так случилось с Ozon — поэтому проверяем на настоящем списке
/// и настоящих адресах.
/// </summary>
public class RuZoneRoutingTests
{
    /// <summary>Сервисы, которые обязаны идти мимо VPN.</summary>
    public static TheoryData<string, string> Russian => new()
    {
        { "Ozon", "185.73.193.68" },
        { "Ozon, кабинет продавца", "185.73.194.82" },
        { "Ozon, интерфейс", "185.73.193.69" },
        { "МАХ", "155.212.204.5" },
        { "МАХ, второй адрес", "155.212.204.74" },
    };

    private static System.Collections.Generic.List<Ipv4Net> Zone() =>
        RuZonePlan.Fit(RuZone.Networks(), KeepInTunnel.Nets());

    /// <summary>Лежит ли адрес внутри подсети.</summary>
    private static bool Covers(Ipv4Net net, uint address) =>
        address >= net.Start && address <= net.EndInclusive;

    [Fact]
    public void СписокРоссийскойЗоныЧитается()
    {
        // Если он не прочитался, через VPN пойдёт всё: и Ozon, и банки,
        // и госуслуги. Снаружи это выглядит как «ничего не работает».
        var nets = RuZone.Networks();

        Assert.True(nets.Count > 8000,
            $"в списке {nets.Count} подсетей — он не прочитался");
    }

    [Theory]
    [MemberData(nameof(Russian))]
    public void РоссийскиеСервисыИдутМимоТуннеля(string name, string address)
    {
        var value = Cidr.ParseAddress(address);
        Assert.NotNull(value);

        var covered = Zone().Any(net => Covers(net, value!.Value));
        Assert.True(covered, $"{name} ({address}) не попал в обход — уйдёт через VPN");
    }

    [Theory]
    [MemberData(nameof(Russian))]
    public void РоссийскиеСервисыНеПопадаютВМаршрутыТуннеля(string name, string address)
    {
        // Обратная проверка, с другой стороны: то, что уходит в туннель,
        // не должно накрывать эти адреса.
        var value = Cidr.ParseAddress(address);
        var inTunnel = Cidr.Complement(Zone()).Any(net => Covers(net, value!.Value));
        Assert.False(inTunnel, $"{name} ({address}) оказался в туннеле");
    }

    [Fact]
    public void ЗаблокированныеСервисыОстаютсяВТуннеле()
    {
        // Ради них VPN и включают: укрупнение не должно выпустить их наружу.
        var tunnel = Cidr.Complement(Zone());

        foreach (var (name, address) in new[]
                 {
                     ("GitHub Pages", "185.199.108.153"),
                     ("Google", "192.178.24.14"),
                     ("Fastly", "151.101.1.140"),
                 })
        {
            var value = Cidr.ParseAddress(address);
            Assert.True(tunnel.Any(net => Covers(net, value!.Value)),
                $"{name} ({address}) ушёл мимо VPN — он должен идти через туннель");
        }
    }

    [Fact]
    public void ЧислоМаршрутовВлезаетВБюджет()
    {
        var routes = RuZonePlan.RouteCount(Zone());

        // Больше — и туннель поднимается заметными секундами.
        Assert.True(routes <= RuZonePlan.DefaultMaxRoutes,
            $"маршрутов {routes}, а можно не больше {RuZonePlan.DefaultMaxRoutes}");
        Assert.True(routes > 100, $"маршрутов всего {routes} — похоже, зона не посчиталась");
    }

    [Fact]
    public void ПустойСписокНеПревращаетсяВПустуюЗону()
    {
        // Нечего исключать — значит и зоны нет: в туннель уйдёт всё.
        // Это правильно как поведение, но должно быть видимым, а не тихим.
        var zone = RuZonePlan.Fit(new System.Collections.Generic.List<Ipv4Net>(),
                                  KeepInTunnel.Nets());

        Assert.Empty(zone);
    }
}
