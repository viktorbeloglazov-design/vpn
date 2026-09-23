using System;
using System.Diagnostics;
using System.Linq;
using System.Runtime.Versioning;
using Microsoft.Win32;

namespace QPVPN.Core;

/// <summary>
/// Ставит и снимает правило разрешения имён для сервисов.
///
/// Windows умеет разрешать разные имена через разные серверы — этим и
/// пользуемся. Правило живёт только пока туннель поднят: снимается при
/// отключении, при выходе из программы и при её следующем запуске, чтобы
/// после неожиданного закрытия ничего не осталось висеть.
/// </summary>
[SupportedOSPlatform("windows")]
public static class SplitDns
{
    private const string PolicyPath =
        @"SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DnsPolicyConfig";

    /// <summary>Своё правило держим отдельно от чужих — по имени.</summary>
    private const string RuleName = "QPVPN";

    /// <summary>Ставит правило. Возвращает false, если не получилось.</summary>
    public static bool Apply(bool servicesThroughVpn)
    {
        var names = SplitDnsRules.Names(servicesThroughVpn);
        if (names.Count == 0)
        {
            Remove();
            return true;
        }

        try
        {
            using var policies = Registry.LocalMachine.CreateSubKey(PolicyPath, writable: true);
            if (policies is null) return false;

            using var rule = policies.CreateSubKey(RuleName, writable: true);
            if (rule is null) return false;

            rule.SetValue("Version", 2, RegistryValueKind.DWord);
            rule.SetValue("Name", names.ToArray(), RegistryValueKind.MultiString);
            rule.SetValue("GenericDNSServers", SplitDnsRules.ServerList(), RegistryValueKind.String);
            rule.SetValue("ConfigOptions", 0x8, RegistryValueKind.DWord);
            rule.SetValue("IPSECCARestriction", "", RegistryValueKind.String);
            rule.SetValue("DisplayName", "QP VPN: имена сервисов через VPN", RegistryValueKind.String);

            Flush();
            return true;
        }
        catch (Exception)
        {
            // Не вышло — сервисы всё равно пойдут через туннель по адресам,
            // просто YouTube может достаться придушенный кэш провайдера.
            return false;
        }
    }

    /// <summary>Снимает правило. Если его нет — молча ничего не делает.</summary>
    public static void Remove()
    {
        try
        {
            using var policies = Registry.LocalMachine.OpenSubKey(PolicyPath, writable: true);
            if (policies is null) return;
            if (!policies.GetSubKeyNames().Contains(RuleName)) return;

            policies.DeleteSubKeyTree(RuleName, throwOnMissingSubKey: false);
            Flush();
        }
        catch (Exception)
        {
            // Права не позволили — правило снимется при следующем запуске
            // от администратора.
        }
    }

    /// <summary>
    /// Просит Windows забыть прежние ответы.
    ///
    /// Без этого имена, разрешённые до включения VPN, продолжат указывать
    /// на старые адреса, пока не истечёт их срок.
    /// </summary>
    private static void Flush()
    {
        try
        {
            var info = new ProcessStartInfo("ipconfig", "/flushdns")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            using var process = Process.Start(info);
            process?.WaitForExit(5_000);
        }
        catch (Exception)
        {
            // Старые ответы доживут свой срок сами.
        }
    }
}
