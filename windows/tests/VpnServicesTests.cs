using System;
using System.Linq;
using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Что уходит в туннель, а что идёт мимо.
///
/// Правило простое: через VPN идёт рабочая зона для 1С и, если включён
/// переключатель, четыре сервиса. Всё остальное идёт мимо VPN напрямую.
/// Адрес сервиса, не попавший в список, означает, что сервис не
/// открывается; лишний адрес — что через VPN пошло то, чему там не место.
///
/// Отдельно проверяется главное: ни один российский сайт не должен
/// попадать в туннель — даже тот, который стоит за тем же посредником,
/// что и нужные сервисы.
/// </summary>
public class VpnServicesTests
{
    /// <summary>Живые адреса, которые эти сайты отдавали при проверке.</summary>
    public static TheoryData<string, string> ЖивыеАдресаСервисов => new()
    {
        { "Claude", "160.79.104.10" },
        { "Claude, обращения программ", "160.79.104.11" },
        { "WhatsApp", "57.144.205.32" },
        { "WhatsApp, файлы", "157.240.254.60" },
        { "YouTube", "142.251.150.4" },
        { "YouTube", "108.177.121.136" },
        { "YouTube, мобильный", "74.125.132.100" },
        { "YouTube, картинки", "173.194.193.119" },
        { "YouTube, картинки", "192.178.212.119" },
        { "YouTube, api", "172.217.112.4" },
        { "YouTube, заставки", "209.85.200.100" },
        { "YouTube, видео", "172.217.133.166" },
        { "YouTube, видео", "74.125.202.136" },
        { "YouTube, видео", "173.194.195.100" },
    };

    /// <summary>
    /// Российские сайты, которые через VPN идти не должны.
    ///
    /// Первые два здесь не случайно: они стоят на тех же сетях Cloudflare,
    /// где живёт ChatGPT. Пока в списке были сети Cloudflare целиком, эти
    /// сайты уезжали в туннель вместе с ним — ровно то, чего быть не должно.
    /// </summary>
    public static TheoryData<string, string> РоссийскиеАдреса => new()
    {
        { "Рутрекер, за Cloudflare", "104.21.32.39" },
        { "Рутрекер, за Cloudflare", "172.67.182.196" },
        { "Хабр", "178.248.237.68" },
        { "Пикабу", "185.178.210.201" },
        { "vc.ru", "185.65.149.135" },
        { "DNS-Шоп", "185.65.148.196" },
        { "Лента.ру", "81.19.72.32" },
        { "2ГИС", "91.236.49.6" },
        { "Кинопоиск", "213.180.199.9" },
        { "Спортмастер", "178.248.232.80" },
        { "Ситилинк", "178.248.234.66" },
        { "Ozon", "185.73.193.68" },
        { "Ozon, продавцам", "185.73.194.82" },
        { "МАХ", "155.212.204.5" },
        { "МАХ", "155.212.204.140" },
        { "Сбербанк", "194.54.14.140" },
        { "Яндекс", "77.88.55.88" },
        { "домашний роутер", "192.168.1.1" },
    };

    /// <summary>
    /// Чужие сайты на арендованных мощностях.
    ///
    /// Google Cloud и Firebase сдаются в аренду кому угодно, включая
    /// российские компании. Раньше эти сети были в списке заодно с самим
    /// Google — теперь их там нет.
    /// </summary>
    public static TheoryData<string, string> АрендованныеМощности => new()
    {
        { "Google Cloud", "34.117.59.81" },
        { "Google Cloud", "35.190.80.1" },
        { "Google Cloud, балансировщик", "130.211.3.1" },
        { "Firebase, чужие сайты", "199.36.158.100" },
    };

    private static bool Покрыт(string address)
    {
        var value = Cidr.ParseAddress(address);
        Assert.NotNull(value);
        return VpnServices.Nets().Any(net => value >= net.Start && value <= net.EndInclusive);
    }

    [Theory]
    [MemberData(nameof(ЖивыеАдресаСервисов))]
    public void АдресаСервисовПопадаютВТуннель(string name, string address)
    {
        Assert.True(Покрыт(address), $"{name} ({address}) не попал в список — сервис не откроется");
    }

    [Theory]
    [MemberData(nameof(РоссийскиеАдреса))]
    public void РоссийскийТрафикИдётМимоТуннеля(string name, string address)
    {
        Assert.False(Покрыт(address), $"{name} ({address}) пошёл бы через VPN, а должен напрямую");
    }

    [Theory]
    [MemberData(nameof(АрендованныеМощности))]
    public void ЧужиеСайтыНаАрендованныхМощностяхИдутМимо(string name, string address)
    {
        Assert.False(Покрыт(address), $"{name} ({address}) пошёл бы через VPN, а должен напрямую");
    }

    [Fact]
    public void СетейПосредниковВСпискеНет()
    {
        // Сети Cloudflare и Google Cloud — общежития: рядом с нужным
        // сервисом там стоят тысячи чужих сайтов. Взять такую сеть целиком
        // значит увести в туннель чужой трафик.
        foreach (var сеть in new[]
                 {
                     "104.16.0.0/13", "104.24.0.0/14", "172.64.0.0/13", "162.158.0.0/15",
                     "141.101.64.0/18", "108.162.192.0/18", "188.114.96.0/20",
                     "34.64.0.0/10", "35.184.0.0/13", "130.211.0.0/16", "199.36.154.0/23",
                     "23.236.48.0/20", "146.148.0.0/17",
                 })
        {
            var подсеть = Cidr.Parse(сеть)!.Value;
            Assert.DoesNotContain(VpnServices.Nets(), net =>
                net.Start <= подсеть.Start && net.EndInclusive >= подсеть.EndInclusive);
        }
    }

    [Fact]
    public void УChatGPTСобственныхСетейНетИЭтоНарочно()
    {
        // ChatGPT целиком стоит на Cloudflare. Собственной сети у него нет,
        // а чужую брать нельзя — поэтому он ходит через VPN по точным
        // адресам, которые назвал DNS.
        var chatGpt = VpnServices.Services.Single(service => service.Title == "ChatGPT");
        Assert.Empty(chatGpt.Networks);
        Assert.NotEmpty(chatGpt.Domains);
        Assert.Contains("chatgpt.com", chatGpt.Domains);
        Assert.Contains("api.openai.com", chatGpt.Domains);
    }

    [Fact]
    public void ПодменённыйОтветDnsНеПринимаетсяЗаАдресСервиса()
    {
        // На заблокированное имя провайдер отвечает адресом своей заглушки:
        // адрес живой и публичный, но сервису не принадлежит. Проложить
        // к нему маршрут значит увести в туннель чужой трафик.
        foreach (var (name, address) in new[]
                 {
                     ("заглушка провайдера", "62.33.207.196"),
                     ("российский хостинг", "185.73.193.68"),
                     ("Яндекс", "77.88.55.88"),
                     ("домашний роутер", "192.168.1.1"),
                     ("ноль", "0.0.0.0"),
                 })
        {
            Assert.False(VpnServices.IsServiceAddress(Cidr.Parse(address)!.Value),
                $"{name} ({address}) приняли за адрес сервиса");
        }
    }

    [Fact]
    public void НастоящийОтветDnsПринимается()
    {
        foreach (var (name, address) in new[]
                 {
                     ("ChatGPT, Cloudflare", "104.18.32.47"),
                     ("ChatGPT, Cloudflare", "172.64.155.209"),
                     ("OpenAI, обращения программ", "162.159.140.245"),
                     ("Claude", "160.79.104.10"),
                     ("YouTube", "142.251.150.4"),
                     ("WhatsApp", "57.144.205.32"),
                 })
        {
            Assert.True(VpnServices.IsServiceAddress(Cidr.Parse(address)!.Value),
                $"{name} ({address}) не приняли за адрес сервиса — он не попадёт в туннель");
        }
    }

    [Fact]
    public void СетиВладельцевСлужатТолькоПроверкой()
    {
        // Адрес Cloudflare проходит проверку — но сама сеть Cloudflare
        // в туннель не уходит: рядом с ChatGPT там стоят чужие сайты.
        Assert.True(VpnServices.IsServiceAddress(Cidr.Parse("104.18.32.47")!.Value));
        Assert.False(Покрыт("104.18.32.47"));
        Assert.False(Покрыт("104.21.32.39"));
    }

    [Fact]
    public void ВСпискеЧетыреСервиса()
    {
        Assert.Equal(["ChatGPT", "Claude", "YouTube", "WhatsApp"], VpnServices.Titles);
    }

    [Fact]
    public void УКаждогоСервисаЕстьИИменаИПравилаРазрешения()
    {
        foreach (var service in VpnServices.Services)
        {
            Assert.True(service.Domains.Length > 0, $"{service.Title}: нет имён");
            Assert.True(service.Suffixes.Length > 0, $"{service.Title}: нет правил разрешения имён");
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
    public void ВсеИменаВыглядятКакИмена()
    {
        foreach (var service in VpnServices.Services)
        foreach (var domain in service.Domains)
        {
            Assert.True(Cidr.IsDomain(domain), $"{service.Title}: «{domain}» не похоже на имя");
        }
    }

    [Fact]
    public void ИменаСервисовРазрешаютсяЧерезVpn()
    {
        var имена = SplitDnsRules.Names(servicesThroughVpn: true);

        foreach (var нужное in new[]
                 {
                     ".googlevideo.com", ".youtube.com", ".chatgpt.com",
                     ".openai.com", ".anthropic.com", ".whatsapp.net",
                 })
        {
            Assert.Contains(нужное, имена);
        }

        // Чужих имён в правиле быть не должно: остальное разрешает
        // провайдер, как и раньше.
        Assert.DoesNotContain(имена, name => name.EndsWith(".ru", StringComparison.Ordinal));
    }

    [Fact]
    public void БезПереключателяИменаРазрешаетПровайдер()
    {
        Assert.Empty(SplitDnsRules.Names(servicesThroughVpn: false));
    }

    [Fact]
    public void СерверыИмёнТожеИдутЧерезТуннель()
    {
        // Иначе вопрос уйдёт мимо VPN и вернётся ответ провайдера.
        Assert.Equal(2, SplitDnsRules.ServerNets().Count);
        Assert.All(SplitDnsRules.ServerNets(), net => Assert.Equal(32, net.Prefix));
        Assert.Equal("8.8.8.8;1.1.1.1", SplitDnsRules.ServerList());
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
