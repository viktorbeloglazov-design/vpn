using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Когда считать туннель поднявшимся.
///
/// Это решение было источником поломки на Windows: запущенную службу
/// принимали за работающий туннель, проверяли связь раньше, чем она
/// появлялась, и уходили перенастраивать туннель по кругу. Отправка шла,
/// приёма не было, адрес не определялся.
/// </summary>
public class TunnelReadinessTests
{
    [Fact]
    public void СлужбаЗапущенаИСерверОтветилЭтоГотово()
    {
        var report = TunnelReadiness.Parse(
            """{"running":true,"state":"running","rxBytes":4096,"txBytes":2048,"lastHandshake":1758518000}""");

        Assert.True(report.IsReady);
        Assert.Equal(4096, report.RxBytes);
        Assert.Equal(2048, report.TxBytes);
    }

    [Fact]
    public void ЗапущеннаяСлужбаБезОтветаСервераЭтоЕщёНеТуннель()
    {
        // Служба поднялась, адаптер создан, маршруты проложены — но с той
        // стороны пока тишина. Проверять связь сейчас бессмысленно.
        var report = TunnelReadiness.Parse(
            """{"running":true,"state":"running","rxBytes":0,"txBytes":592,"lastHandshake":0}""");

        Assert.False(report.IsReady);
        Assert.True(report.Running);
    }

    [Fact]
    public void ОстановленнаяСлужбаНеГотова()
    {
        var report = TunnelReadiness.Parse("""{"running":false,"state":"stopped"}""");

        Assert.False(report.IsReady);
        Assert.False(report.Running);
    }

    [Fact]
    public void СлужбаЕщёЗапускаетсяИОтвечаетНеполно()
    {
        var report = TunnelReadiness.Parse("""{"running":true,"state":"starting"}""");

        Assert.False(report.IsReady);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("не json")]
    [InlineData("{")]
    [InlineData("[1,2,3]")]
    [InlineData("null")]
    public void НепонятныйОтветНеСчитаетсяГотовностью(string answer)
    {
        // Молчание или мусор — повод подождать ещё, а не объявить связь.
        Assert.False(TunnelReadiness.Parse(answer).IsReady);
    }

    [Fact]
    public void СтрокаВместоЧислаНеЛоматетРазбор()
    {
        var report = TunnelReadiness.Parse(
            """{"running":true,"lastHandshake":"много","rxBytes":"?"}""");

        Assert.False(report.IsReady);
        Assert.Equal(0, report.RxBytes);
    }

    [Fact]
    public void ОшибкаСлужбыНеМешаетПрочитатьОстальное()
    {
        var report = TunnelReadiness.Parse(
            """{"running":true,"lastHandshake":1758518000,"error":"служба не отвечает"}""");

        Assert.True(report.IsReady);
    }

    [Fact]
    public void ЛишниеПоляНеМешают()
    {
        var report = TunnelReadiness.Parse(
            """{"running":true,"lastHandshake":17,"чего-то":"новое","вложенное":{"а":1}}""");

        Assert.True(report.IsReady);
    }
}

/// <summary>
/// Что показывается человеку, пока связи ещё нет.
///
/// Программа писала «Подключён», едва служба запускалась, — и не меняла
/// этого, сколько бы ни было нулей в приёме. Человек видел зелёную
/// надпись и гадал, почему ничего не открывается.
/// </summary>
public class ConnectedStateTests
{
    [Fact]
    public void ЗапущеннаяСлужбаБезПриветствияЭтоНеПодключение()
    {
        var report = TunnelReadiness.Parse(
            """{"running":true,"rxBytes":0,"txBytes":15561,"lastHandshake":0}""");

        // Ровно то, что было на экране: отправлено 15 КБ, принято 0.
        Assert.False(report.IsReady);
        Assert.Equal(0, report.RxBytes);
        Assert.Equal(15561, report.TxBytes);
    }

    [Fact]
    public void ПоявилосьПриветствиеЗначитСвязьЕсть()
    {
        var report = TunnelReadiness.Parse(
            """{"running":true,"rxBytes":4096,"txBytes":15561,"lastHandshake":1758600000}""");

        Assert.True(report.IsReady);
    }
}
