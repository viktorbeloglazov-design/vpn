using System.Linq;
using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Сколько времени человек ждёт подключения.
///
/// Подбор размера пакета полезен, но каждая попытка — это перезапуск
/// службы и ожидание ответа сервера. Стоило добавить ожидание, не считая
/// общего времени, и подключение растянулось на минуты: на экране висела
/// одна надпись, и программа выглядела повисшей.
/// </summary>
public class ConnectTimeTests
{
    private const string Server = "91.201.0.1:51820";
    private const string Backup = "95.213.0.1:31984";

    /// <summary>Сколько секунд занимает одна попытка: перезапуск и ожидание.</summary>
    private const int SecondsPerAttempt = 8 + 3;

    [Fact]
    public void ПодборНеРастягиваетсяНаМинуты()
    {
        var plan = TuningPlan.Build([Server, Backup], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 0);
        var seconds = plan.Count * SecondsPerAttempt;

        // Полторы минуты — предел, после которого человек считает, что всё
        // зависло, и выключает программу.
        Assert.True(seconds <= 90,
            $"подбор занял бы {seconds} с — это дольше, чем кто-либо готов ждать");
    }

    [Fact]
    public void ОдинВходПодбираетсяБыстро()
    {
        var plan = TuningPlan.Build([Server], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 0);
        var seconds = plan.Count * SecondsPerAttempt;

        Assert.True(seconds <= 45, $"подбор занял бы {seconds} с");
    }

    [Fact]
    public void ВыбранныйВручнуюРазмерПочтиНеТребуетВремени()
    {
        // Человек задал размер сам — перебирать нечего.
        var plan = TuningPlan.Build([Server], profileMtu: 1420, chosenMtu: 1280, rememberedMtu: 0);

        Assert.Empty(plan);
    }

    [Fact]
    public void ЗапомненныйРазмерСокращаетПодбор()
    {
        var сНуля = TuningPlan.Build([Server], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 0);
        var сПамятью = TuningPlan.Build([Server], profileMtu: 1420, chosenMtu: 0, rememberedMtu: 1320);

        // Прошлый успешный размер — подсказка: с ним попыток меньше.
        Assert.True(сПамятью.Count < сНуля.Count,
            "запомненный размер должен сокращать подбор, а не удлинять");
    }
}
