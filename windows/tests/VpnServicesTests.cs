using System.Linq;
using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Что уходит в туннель, а что идёт мимо.
///
/// Правило простое: через VPN идёт рабочая зона для 1С и, если включён
/// переключатель, список сервисов. Всё остальное — мимо. Адрес сервиса,
/// не попавший в список, означает, что сервис не открывается; лишний
/// адрес — что через VPN пошло то, чему там не место.
/// </summary>
public class VpnServicesTests
{
    /// <summary>Живые адреса, которые эти сайты отдавали при проверке.</summary>
    public static TheoryData<string, string> Живые => new()
    {
        { "ChatGPT", "104.18.32.47" },
        { "ChatGPT", "172.64.155.209" },
        { "ChatGPT, вход", "172.65.90.20" },
        { "OpenAI, api", "162.159.140.245" },
        { "Claude", "160.79.104.10" },
        { "WhatsApp", "57.144.205.32" },
        { "YouTube", "142.251.150.4" },
        { "YouTube", "108.177.121.136" },
        { "YouTube, мобильный", "74.125.132.100" },
        { "YouTube, картинки", "173.194.193.119" },
        { "YouTube, картинки", "192.178.212.119" },
        { "YouTube, api", "172.217.112.4" },
    };

    private static bool Покрыт(string address)
    {
        var value = Cidr.ParseAddress(address);
        Assert.NotNull(value);
        return VpnServices.Nets().Any(net => value >= net.Start && value <= net.EndInclusive);
    }

    [Theory]
    [MemberData(nameof(Живые))]
    public void АдресаСервисовПопадаютВТуннель(string name, string address)
    {
        Assert.True(Покрыт(address), $"{name} ({address}) не попал в список — сервис не откроется");
    }

    [Fact]
    public void ЧужиеАдресаВТуннельНеПопадают()
    {
        // Через VPN должен идти только список. Всё прочее — мимо, иначе
        // теряется весь смысл: российские сайты снова увидят чужую страну.
        foreach (var (name, address) in new[]
                 {
                     ("Ozon", "185.73.193.68"),
                     ("МАХ", "155.212.204.5"),
                     ("Сбербанк", "194.54.14.140"),
                     ("домашний роутер", "192.168.1.1"),
                     ("Яндекс", "77.88.55.88"),
                 })
        {
            Assert.False(Покрыт(address), $"{name} ({address}) попал в туннель, а не должен");
        }
    }

    [Fact]
    public void ВСпискеЧетыреСервиса()
    {
        Assert.Equal(["ChatGPT", "Claude", "WhatsApp", "YouTube"], VpnServices.Titles);
    }

    [Fact]
    public void УКаждогоСервисаЕстьИПодсетиИИмена()
    {
        foreach (var service in VpnServices.Services)
        {
            Assert.True(service.Networks.Length > 0, $"{service.Title}: нет подсетей");
            Assert.True(service.Domains.Length > 0, $"{service.Title}: нет имён");
        }
    }

    [Fact]
    public void ВсеПодсетиРазбираются()
    {
        foreach (var service in VpnServices.Services)
        foreach (var text in service.Networks)
        {
            Assert.True(Cidr.Parse(text) is not null, $"{service.Title}: не разобралось «{text}»");
        }
    }

    [Fact]
    public void РабочаяЗонаДляОдинСЭтоДваАдресаСервера()
    {
        Assert.Equal(2, OneCZone.Count);
        Assert.Equal(["135.106.142.73"], OneCZone.Hosts);
    }

    [Fact]
    public void АдресОдинСРазбираетсяКакПодсеть()
    {
        // Иначе он уйдёт в DNS как имя, и подключение будет ждать ответа,
        // которого не будет.
        foreach (var host in OneCZone.Hosts)
        {
            Assert.True(Cidr.Parse(host) is not null, $"«{host}» не разобралось как адрес");
        }
    }
}
