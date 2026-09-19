using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace QPVPN.Core;

/// <summary>Что уходит в туннель.</summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum TunnelMode
{
    /// <summary>Весь трафик через VPN.</summary>
    Full,

    /// <summary>Через VPN идут только адреса из правил.</summary>
    Include,

    /// <summary>Через VPN идёт всё, кроме адресов из правил.</summary>
    Exclude,
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum RuleKind
{
    Domain,
    Cidr,
}

public sealed class RoutingRule
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public RuleKind Kind { get; set; } = RuleKind.Domain;
    public string Value { get; set; } = "";
    public bool Enabled { get; set; } = true;
    public string Note { get; set; } = "";
}

public sealed class AppConfig
{
    public int Version { get; set; } = 1;

    /// <summary>Главный фильтр: через VPN идёт только то, что не работает из России.</summary>
    public bool MainFilter { get; set; } = true;

    /// <summary>Рабочие ресурсы: заложенные адреса идут через VPN.</summary>
    public bool WorkFilter { get; set; } = true;

    public TunnelMode Mode { get; set; } = TunnelMode.Full;
    public List<RoutingRule> Rules { get; set; } = new();

    /// <summary>Использовать DNS-серверы из профиля.</summary>
    public bool UseTunnelDns { get; set; } = true;

    /// <summary>Вся российская зона идёт мимо туннеля.</summary>
    public bool BypassRuZone { get; set; } = true;

    /// <summary>Режим, который действительно применяется с учётом главного фильтра.</summary>
    [JsonIgnore]
    public TunnelMode EffectiveMode => MainFilter ? TunnelMode.Include : Mode;

    [JsonIgnore]
    public IEnumerable<RoutingRule> ActiveRules
    {
        get
        {
            foreach (var rule in Rules)
            {
                if (rule.Enabled && !string.IsNullOrWhiteSpace(rule.Value)) yield return rule;
            }
        }
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
                Config = JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(ConfigPath), Options) ?? new AppConfig();
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
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(Config, Options));
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
