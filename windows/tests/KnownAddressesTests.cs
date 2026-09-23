using System;
using System.Linq;
using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Память адресов сервисов.
///
/// ChatGPT отвечает с адресов, которые время от времени меняются. Если
/// помнить только сегодняшний ответ, после смены адреса сайт перестанет
/// открываться до переподключения — поэтому адреса накапливаются.
/// </summary>
public class KnownAddressesTests
{
    private static readonly DateTimeOffset Сегодня = new(2026, 9, 23, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void ВчерашнийАдресНеТеряется()
    {
        var было = new[] { new KnownAddresses.Entry("104.18.32.47", Сегодня.AddDays(-3)) };
        var стало = KnownAddresses.Merge(было, ["172.64.155.209"], Сегодня);

        Assert.Equal(2, стало.Count);
        Assert.Contains(стало, entry => entry.Address == "104.18.32.47");
        Assert.Contains(стало, entry => entry.Address == "172.64.155.209");
    }

    [Fact]
    public void АдресКоторыйНеВстречалсяМесяцЗабывается()
    {
        var было = new[]
        {
            new KnownAddresses.Entry("104.18.32.47", Сегодня.AddDays(-40)),
            new KnownAddresses.Entry("172.64.155.209", Сегодня.AddDays(-2)),
        };
        var стало = KnownAddresses.Merge(было, [], Сегодня);

        Assert.Single(стало);
        Assert.Equal("172.64.155.209", стало[0].Address);
    }

    [Fact]
    public void СегодняшнийОтветОбновляетДату()
    {
        var было = new[] { new KnownAddresses.Entry("104.18.32.47", Сегодня.AddDays(-29)) };
        var стало = KnownAddresses.Merge(было, ["104.18.32.47"], Сегодня);

        Assert.Single(стало);
        Assert.Equal(Сегодня, стало[0].SeenAt);
    }

    [Fact]
    public void ПамятьНеРастётБезКонца()
    {
        var много = Enumerable.Range(0, KnownAddresses.Limit + 50)
            .Select(number => $"104.18.{number / 256}.{number % 256}");

        Assert.Equal(KnownAddresses.Limit, KnownAddresses.Merge([], много, Сегодня).Count);
    }

    [Fact]
    public void МусорВПамятьНеПопадает()
    {
        var стало = KnownAddresses.Merge([], ["не адрес", "999.1.1.1", "104.18.32.47"], Сегодня);

        Assert.Single(стало);
        Assert.Equal("104.18.32.47", стало[0].Address);
    }

    [Fact]
    public void ЗаглушкиНаЗаблокированныеИменаНеСчитаютсяАдресами()
    {
        // Заблокированное имя нередко «разрешается» в ноль или в домашний
        // адрес. Запомнить такой адрес — значит потом гонять через туннель
        // чужой трафик, вплоть до собственного роутера.
        foreach (var заглушка in new[]
                 {
                     "0.0.0.0", "127.0.0.1", "192.168.1.1", "10.8.0.1",
                     "172.16.0.5", "169.254.1.1", "100.64.0.1", "240.0.0.1",
                 })
        {
            Assert.False(Cidr.IsPublicAddress(Cidr.Parse(заглушка)!.Value),
                $"«{заглушка}» приняли за настоящий адрес сервиса");
        }

        foreach (var настоящий in new[] { "104.18.32.47", "160.79.104.10", "142.251.150.4" })
        {
            Assert.True(Cidr.IsPublicAddress(Cidr.Parse(настоящий)!.Value),
                $"«{настоящий}» не приняли за настоящий адрес");
        }
    }

    [Fact]
    public void ЦелаяСетьВПамятьНеКладётся()
    {
        // Память — про точные адреса сервисов. Сеть, попавшая сюда
        // по ошибке, увела бы в туннель чужие сайты.
        Assert.False(Cidr.IsPublicAddress(Cidr.Parse("104.16.0.0/13")!.Value));
    }
}
