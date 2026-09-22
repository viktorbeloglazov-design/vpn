using System.Collections.Generic;
using System.Linq;

namespace QPVPN.Core;

/// <summary>
/// Порядок попыток поднять туннель: каким входом и с каким размером пакета.
///
/// Вынесено отдельно от самого подключения, чтобы порядок можно было
/// проверить, не поднимая ничего на самом деле. Ошибка здесь стоит дорого:
/// каждая лишняя попытка — это переустановка службы, во время которой
/// связи нет.
/// </summary>
public static class TuningPlan
{
    /// <summary>Одна попытка: адрес входа и размер пакета.</summary>
    public readonly record struct Attempt(string Endpoint, int Mtu, bool ViaBackup);

    /// <summary>Размеры пакета сверху вниз: чем больше, тем быстрее.</summary>
    public static readonly int[] MtuLadder = { 1420, 1380, 1320, 1280 };

    /// <summary>
    /// Что пробовать после того, как первая попытка не дала связи.
    /// </summary>
    /// <param name="endpoints">Сервер, затем запасной вход.</param>
    /// <param name="profileMtu">Размер пакета из ключа.</param>
    /// <param name="chosenMtu">Выбранный человеком вручную; 0 — подбирать.</param>
    /// <param name="rememberedMtu">Подошедший в прошлый раз; 0 — не подбирали.</param>
    public static IReadOnlyList<Attempt> Build(
        IReadOnlyList<string> endpoints,
        int profileMtu,
        int chosenMtu,
        int rememberedMtu)
    {
        if (endpoints.Count == 0) return [];

        var ladder = Ladder(profileMtu, chosenMtu, rememberedMtu);

        // Первую попытку уже сделали при подъёме туннеля: сервер, размер
        // пакета из ключа или заданный вручную. Повторять её — значит зря
        // гонять службу туда-обратно.
        var triedMtu = chosenMtu > 0 ? chosenMtu : profileMtu;

        var attempts = new List<Attempt>();
        for (var index = 0; index < endpoints.Count; index++)
        {
            var viaBackup = index > 0;
            foreach (var mtu in ladder)
            {
                if (!viaBackup && mtu == triedMtu) continue;
                attempts.Add(new Attempt(endpoints[index], mtu, viaBackup));
            }
        }
        return attempts;
    }

    /// <summary>
    /// Лесенка размеров пакета: с того, что подошёл в прошлый раз, и ниже.
    /// </summary>
    public static IReadOnlyList<int> Ladder(int profileMtu, int chosenMtu, int rememberedMtu)
    {
        // Выбрали вручную — перебирать нечего, уважаем выбор.
        if (chosenMtu > 0) return new[] { chosenMtu };

        var start = rememberedMtu > 0
            ? rememberedMtu
            : (profileMtu > 0 ? System.Math.Min(profileMtu, MtuLadder[0]) : MtuLadder[0]);

        var ladder = new List<int> { start };
        ladder.AddRange(MtuLadder.Where(value => value < start));
        return ladder;
    }
}
