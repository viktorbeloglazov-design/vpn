using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace QPVPN.Core;

public sealed class AppConfig
{
    public int Version { get; set; } = 1;

    /// <summary>
    /// Сервисы через VPN: ChatGPT, Claude, WhatsApp, YouTube.
    ///
    /// Единственный переключатель в окне. Выключен — через VPN идёт только
    /// рабочая зона для 1С, весь остальной трафик уходит мимо туннеля.
    /// </summary>
    public bool ServicesThroughVpn { get; set; } = true;

    /// <summary>Использовать DNS-серверы из профиля.</summary>
    ///
    /// Через туннель идёт только список, поэтому DNS оставляем свой:
    /// чужой DNS заворачивал бы в туннель и всё остальное.
    public bool UseTunnelDns { get; set; }

    /// <summary>
    /// Размер пакета. 0 — как записано в ключе.
    ///
    /// От него зависит скорость: чем больше, тем лучше, но если сеть такие
    /// пакеты не пропускает, страницы наоборот встают.
    /// </summary>
    public int Mtu { get; set; }

    /// <summary>Что подобралось в прошлый раз. 0 — ещё не подбирали.</summary>
    public int ProbedMtu { get; set; }

    /// <summary>
    /// Запасной вход: адрес:порт узла, который пересылает пакеты на сервер.
    ///
    /// Нужен там, где до сервера напрямую не достучаться. Ключ при этом тот
    /// же самый — узел ничего не расшифровывает, только перебрасывает.
    /// </summary>
    public string BackupEndpoint { get; set; } = "";

    /// <summary>Когда в последний раз смотрели, нет ли обновления.</summary>
    public DateTimeOffset LastUpdateCheck { get; set; }

    /// <summary>Куда пробовать подключаться: сервер, затем запасной вход.</summary>
    public List<string> EndpointsToTry(string primary)
    {
        var backup = BackupEndpoint.Trim();
        return backup.Length == 0 || backup == primary
            ? new List<string> { primary }
            : new List<string> { primary, backup };
    }

    /// <summary>
    /// Настройки, приведённые к зашитому поведению.
    ///
    /// Маршрутизация не настраивается: через VPN идёт рабочая зона для 1С
    /// и, если включён переключатель, список сервисов. Всё остальное —
    /// мимо туннеля. Человек выбирает только этот переключатель и размер
    /// пакета, их здесь не трогаем.
    /// </summary>
    public AppConfig Pinned()
    {
        UseTunnelDns = false;
        return this;
    }
}

/// <summary>
/// Настройки и профиль на диске.
///
/// Настройки — в профиле пользователя, сам ключ — в защищённой папке
/// ProgramData, куда служба туннеля имеет доступ, а обычные программы нет.
/// </summary>
public sealed class Store
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    public static string SettingsDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QPVPN");

    public static string TunnelDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "QPVPN");

    public static string ConfigPath => Path.Combine(SettingsDirectory, "settings.json");
    public static string ProfilePath => Path.Combine(TunnelDirectory, "qpvpn.conf");

    public AppConfig Config { get; private set; } = new();

    public Store()
    {
        Directory.CreateDirectory(SettingsDirectory);
        Load();
    }

    private void Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
            {
                // Что бы ни лежало в файле от прошлых версий, в работу
                // уходит одно и то же поведение: настраивать негде.
                Config = (JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(ConfigPath), Options)
                    ?? new AppConfig()).Pinned();
            }
        }
        catch (Exception)
        {
            Config = new AppConfig();
        }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(SettingsDirectory);
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(Config.Pinned(), Options));
        }
        catch (Exception)
        {
            // Настройки не легли на диск, но в памяти уже применены.
        }
    }

    public bool HasProfile => File.Exists(ProfilePath) && new FileInfo(ProfilePath).Length > 0;

    public string? ProfileText() => HasProfile ? File.ReadAllText(ProfilePath) : null;

    public void ClearProfile()
    {
        try
        {
            if (File.Exists(ProfilePath)) File.Delete(ProfilePath);
        }
        catch (Exception)
        {
            // Файл держит служба — он перезапишется при следующем подключении.
        }
    }
}
