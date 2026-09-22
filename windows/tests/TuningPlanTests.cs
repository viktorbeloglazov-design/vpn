using System.Linq;
using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Порядок попыток поднять туннель.
///
/// Каждая попытка — это перезапуск службы, во время которого связи нет.
/// Лишняя попытка стоит человеку нескольких секунд без интернета, а
/// пропущенная — неработающего VPN.
/// </summary>
public class TuningPlanTests
{
    private const string Server = "91.201.0.1:51820";
    private const string Backup = "95.213.0.1:31984";

    [Fact]
    public void ПервоеСочетаниеНеПовторяется()
    {
        // Туннель уже поднимали сервером с размером пакета из ключа.
        var plan = TuningPlan.Build([Server], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 0);

        Assert.DoesNotContain(plan, a => a.Endpoint == Server && a.Mtu == 1420);
        Assert.Equal([1380, 1320, 1280], plan.Select(a => a.Mtu));
    }

    [Fact]
    public void ЗапасномуВходуДостаютсяВсеРазмеры()
    {
        var plan = TuningPlan.Build([Server, Backup], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 0);

        // Через запасной вход первое сочетание ещё не проверяли,
        // поэтому 1420 для него пропускать нельзя.
        var backup = plan.Where(a => a.ViaBackup).Select(a => a.Mtu).ToArray();
        Assert.Equal([1420, 1380, 1320, 1280], backup);
    }

    [Fact]
    public void СерверПробуетсяРаньшеЗапасногоВхода()
    {
        var plan = TuningPlan.Build([Server, Backup], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 0);

        var firstBackup = plan.ToList().FindIndex(a => a.ViaBackup);
        var lastDirect = plan.ToList().FindLastIndex(a => !a.ViaBackup);
        Assert.True(lastDirect < firstBackup,
            "запасной вход — это крюк, к нему обращаются, только исчерпав прямой путь");
    }

    [Fact]
    public void ЗапомненныйРазмерСтановитсяНачалом()
    {
        // В прошлый раз подошёл 1320 — начинать сверху незачем.
        var plan = TuningPlan.Build([Server], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 1320);

        Assert.Equal([1320, 1280], plan.Select(a => a.Mtu));
    }

    [Fact]
    public void ЗапомненныйРазмерНеПропускаетсяКогдаОнНеПервый()
    {
        // Поднимали с 1420 из ключа, а помним 1320: его надо попробовать,
        // а не пропустить как «уже пробованный».
        var plan = TuningPlan.Build([Server], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 1320);

        Assert.Contains(plan, a => a.Mtu == 1320);
    }

    [Fact]
    public void ВыбранныйВручнуюРазмерНеПеребирается()
    {
        var plan = TuningPlan.Build([Server], profileMtu: 1420, chosenMtu: 1280, rememberedMtu: 0);

        // Прямым путём пробовать нечего: 1280 уже стоял при подъёме.
        Assert.Empty(plan.Where(a => !a.ViaBackup));
    }

    [Fact]
    public void ВыбранныйВручнуюРазмерИдётИЧерезЗапаснойВход()
    {
        var plan = TuningPlan.Build([Server, Backup], profileMtu: 1420, chosenMtu: 1280, rememberedMtu: 0);

        Assert.Equal([new TuningPlan.Attempt(Backup, 1280, true)], plan);
    }

    [Fact]
    public void МаленькийРазмерИзКлючаНеУвеличиваем()
    {
        // В ключе 1280: предлагать 1420 бессмысленно, сервер его не ждёт.
        var ladder = TuningPlan.Ladder(profileMtu: 1280, chosenMtu: 0, rememberedMtu: 0);

        Assert.Equal([1280], ladder);
    }

    [Fact]
    public void БезКлючаИПамятиБерётсяВерхЛесенки()
    {
        var ladder = TuningPlan.Ladder(profileMtu: 0, chosenMtu: 0, rememberedMtu: 0);

        Assert.Equal([1420, 1380, 1320, 1280], ladder);
    }

    [Fact]
    public void РазмерыИдутТолькоВнизИБезПовторов()
    {
        var ladder = TuningPlan.Ladder(profileMtu: 1420, chosenMtu: 0, rememberedMtu: 0).ToList();

        Assert.Equal(ladder.Distinct().Count(), ladder.Count);
        Assert.Equal(ladder.OrderByDescending(value => value), ladder);
    }

    [Fact]
    public void БезВходовПланПустой()
    {
        Assert.Empty(TuningPlan.Build([], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 0));
    }

    [Fact]
    public void ЧислоПопытокОстаётсяРазумным()
    {
        var plan = TuningPlan.Build([Server, Backup], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 0);

        // Каждая попытка — перезапуск службы: связи нет секунды. Их должно
        // быть считанное число, иначе подключение превращается в пытку.
        Assert.True(plan.Count <= 8, $"попыток {plan.Count} — слишком много");
    }
}
