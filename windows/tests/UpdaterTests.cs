using System.IO;
using QPVPN.Core;
using Xunit;

namespace QPVPN.Tests;

/// <summary>
/// Поиск программы в распакованном архиве.
///
/// Архив собирается с папкой внутри, и её имя содержит номер версии —
/// то есть меняется с каждым выпуском. Искать по имени нельзя: обновление
/// перестанет ставиться на следующем же выпуске.
/// </summary>
public class UpdaterTests
{
    private static string Temp()
    {
        var path = Path.Combine(Path.GetTempPath(), "qpvpn-test-" + Path.GetRandomFileName());
        Directory.CreateDirectory(path);
        return path;
    }

    [Fact]
    public void ПрограммаНаходитсяВПодпапкеСВерсией()
    {
        var root = Temp();
        var inner = Path.Combine(root, "QPVPN-windows-2.8.0");
        Directory.CreateDirectory(inner);
        File.WriteAllText(Path.Combine(inner, "QPVPN.exe"), "");

        Assert.Equal(inner, Updater.FindProgramDirectory(root));
    }

    [Fact]
    public void ПрограммаНаходитсяИВКорнеАрхива()
    {
        var root = Temp();
        File.WriteAllText(Path.Combine(root, "QPVPN.exe"), "");

        Assert.Equal(root, Updater.FindProgramDirectory(root));
    }

    [Fact]
    public void ПрограммаНаходитсяНаЛюбойГлубине()
    {
        var root = Temp();
        var deep = Path.Combine(root, "а", "б", "в");
        Directory.CreateDirectory(deep);
        File.WriteAllText(Path.Combine(deep, "QPVPN.exe"), "");

        Assert.Equal(deep, Updater.FindProgramDirectory(root));
    }

    [Fact]
    public void БезПрограммыНичегоНеНаходится()
    {
        var root = Temp();
        File.WriteAllText(Path.Combine(root, "ЧИТАЙ-МЕНЯ.txt"), "");

        // Чужой архив не должен сойти за обновление: иначе помощник
        // разложит поверх рабочей папки неизвестно что.
        Assert.Null(Updater.FindProgramDirectory(root));
    }

    [Fact]
    public void БитыйАрхивНеСтавится()
    {
        var archive = Path.Combine(Temp(), "битый.zip");
        File.WriteAllText(archive, "это не архив");

        var outcome = Updater.Install(archive, Temp());

        var failed = Assert.IsType<Updater.Outcome.Failed>(outcome);
        Assert.Contains("распаков", failed.Reason);
    }
}
