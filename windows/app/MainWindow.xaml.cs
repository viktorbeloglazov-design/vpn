using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using QPVPN.Core;
using ZXing;
using ZXing.Common;

namespace QPVPN;

public partial class MainWindow : Window
{
    private readonly Store _store = new();
    private readonly TunnelController _tunnel;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(2) };

    /// <summary>
    /// Повторная проверка обновления у программы, которую не закрывают.
    ///
    /// Одной проверки при запуске мало: окно висит неделями. Суточный
    /// промежуток выдерживается внутри самой проверки.
    /// </summary>
    private readonly DispatcherTimer _updateTimer = new() { Interval = TimeSpan.FromHours(6) };

    private bool _loading = true;
    private bool _busy;

    public MainWindow()
    {
        InitializeComponent();
        _tunnel = new TunnelController(_store);

        Loaded += async (_, _) =>
        {
            ApplyConfigToControls();
            _loading = false;
            Render();
            await RefreshAsync();
            _timer.Tick += async (_, _) => await RefreshAsync();
            _timer.Start();
            await CheckForUpdateAsync(force: false);
            _updateTimer.Tick += async (_, _) => await CheckForUpdateAsync(force: false);
            _updateTimer.Start();
        };
    }

    // MARK: - Отрисовка

    private void ApplyConfigToControls()
    {
        var config = _store.Config;
        WorkFilterSwitch.IsChecked = config.WorkFilter;
        BackupEndpointBox.Text = config.BackupEndpoint;
        Mtu1420.IsChecked = config.Mtu == 1420;
        MtuKey.IsChecked = config.Mtu == 0;
        Mtu1380.IsChecked = config.Mtu == 1380;
        Mtu1280.IsChecked = config.Mtu == 1280;
    }

    private void Render()
    {
        if (_loading) return;

        var config = _store.Config;
        var status = _tunnel.Status;

        StateTitle.Text = status.State switch
        {
            ConnectionState.Connected => "Подключён",
            ConnectionState.Connecting => "Подключение…",
            ConnectionState.Error => "Ошибка",
            _ => "Выключен",
        };

        StateTitle.Foreground = status.State switch
        {
            ConnectionState.Connected => (System.Windows.Media.Brush)FindResource("Connected"),
            ConnectionState.Connecting => (System.Windows.Media.Brush)FindResource("Waiting"),
            ConnectionState.Error => (System.Windows.Media.Brush)FindResource("Danger"),
            _ => (System.Windows.Media.Brush)FindResource("OnSurface"),
        };

        if (status.State == ConnectionState.Connected)
        {
            // Внизу приписываем то, что человек сам не увидит: каким входом
            // поднялась связь и какой размер пакета в итоге подошёл.
            var parts = new List<string> { $"Сервер {status.ServerName}", $"маршрутов: {status.RouteCount}" };
            if (_tunnel.UsedBackupEntry) parts.Add("через запасной вход");
            if (_tunnel.ActiveMtu > 0) parts.Add($"пакет {_tunnel.ActiveMtu}");
            StateSubtitle.Text = string.Join(" · ", parts);
        }
        else
        {
            StateSubtitle.Text = status.Message.Length > 0
                ? status.Message
                : _store.HasProfile ? "Ключ загружен" : "Ключ не загружен";
        }

        PowerButton.Content = status.State == ConnectionState.Connected ? "Выключить" : "Включить";
        PowerButton.IsEnabled = !_busy;
        PowerButton.Background = status.State == ConnectionState.Connected
            ? (System.Windows.Media.Brush)FindResource("Ocean")
            : (System.Windows.Media.Brush)FindResource("SurfaceVariant");

        RxText.Text = status.State == ConnectionState.Connected ? Bytes(status.RxBytes) : "—";
        TxText.Text = status.State == ConnectionState.Connected ? Bytes(status.TxBytes) : "—";

        MasterText.Text = $"Российские сайты — МАХ, госуслуги, банки, маркетплейсы — напрямую "
            + $"({RuZone.Count} подсетей России)";
        MasterHint.Text = status.RouteCount > 0
            ? $"Маршрутов в туннеле: {status.RouteCount}"
            : $"Встроенный список сервисов: {MasterFilter.Count}";

        WorkHint.Text = $"{WorkFilter.Count} адреса · заложены в приложение";
        WorkList.Text = string.Join("\n", WorkFilter.Resources.Select(resource => $"{resource.Title}  {resource.Url}"));

        ProfileText.Text = _store.HasProfile ? ProfileSummary() : "Ключа нет. Вставьте ссылку vpn:// или откройте файл.";
        ClearProfileButton.Visibility = _store.HasProfile ? Visibility.Visible : Visibility.Collapsed;

        VersionText.Text = $"QP VPN {AppVersion} · AmneziaWG и WireGuard";
    }

    private string ProfileSummary()
    {
        try
        {
            var profile = WgProfile.Parse(_store.ProfileText() ?? "");
            return $"{profile.ProtocolName} · {profile.EndpointHost}";
        }
        catch (Exception)
        {
            return "Ключ сохранён, но прочитать его не удалось.";
        }
    }

    private static string Bytes(long value)
    {
        string[] units = { "Б", "КБ", "МБ", "ГБ", "ТБ" };
        double size = value;
        var unit = 0;
        while (size >= 1024 && unit < units.Length - 1)
        {
            size /= 1024;
            unit++;
        }
        return unit == 0 ? $"{value} {units[0]}" : $"{size:0.#} {units[unit]}";
    }

    // MARK: - Включение

    private async void OnPowerClicked(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        _busy = true;
        Render();

        try
        {
            if (_tunnel.Status.State == ConnectionState.Connected)
            {
                await _tunnel.DisconnectAsync();
            }
            else
            {
                StateSubtitle.Text = "Считаю маршруты…";
                await _tunnel.ConnectAsync();
            }
        }
        finally
        {
            _busy = false;
            Render();
        }
    }

    private async Task RefreshAsync()
    {
        if (_busy) return;
        await _tunnel.RefreshAsync();
        Render();
    }

    // MARK: - Переключатели

    private void OnWorkFilterChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _store.Config.WorkFilter = WorkFilterSwitch.IsChecked == true;
        _store.Save();
        Render();
        _ = ReapplyAsync();
    }

    /// <summary>
    /// Запасной вход: узел, который пересылает пакеты на сервер.
    ///
    /// Ключ при этом не меняется, поэтому и переподключаться незачем —
    /// адрес пригодится при следующем включении.
    /// </summary>
    private void OnBackupEndpointChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _store.Config.BackupEndpoint = BackupEndpointBox.Text.Trim();
        _store.Save();
    }

    // MARK: - Обновление

    /// <summary>
    /// Смотрит, не вышла ли новая версия.
    ///
    /// Программа ставится архивом с сайта, мимо магазина: напомнить о новой
    /// версии некому, поэтому смотрим сами — раз в сутки.
    /// </summary>
    private async Task CheckForUpdateAsync(bool force)
    {
        var now = DateTimeOffset.UtcNow;
        if (!force && now - _store.Config.LastUpdateCheck < UpdateCheck.CheckInterval) return;

        var latest = await UpdateCheck.LatestVersionAsync();

        if (latest is null)
        {
            // Неудачу за проверку не засчитываем. Иначе один сбой связи
            // означал бы, что программа промолчит целые сутки — и человек
            // всё это время сидит на старой версии, не зная об этом.
            UpdateCard.Visibility = Visibility.Collapsed;
            if (force)
            {
                UpdateStateText.Text = "Не удалось спросить сервер. Проверьте связь "
                    + $"или скачайте вручную: {UpdateCheck.PageUrl} (у вас {AppVersion}).";
            }
            return;
        }

        _store.Config.LastUpdateCheck = now;
        _store.Save();

        if (!UpdateCheck.IsNewer(latest, AppVersion))
        {
            UpdateCard.Visibility = Visibility.Collapsed;
            if (force) UpdateStateText.Text = $"Установлена последняя версия {AppVersion}.";
            return;
        }

        _updateVersion = latest;
        UpdateTitle.Text = $"Вышла версия {latest}";
        UpdateHint.Text = $"Установлена {AppVersion}. Скачается архив — распакуйте его поверх "
            + "текущей папки с заменой. Ключ и настройки останутся на месте.";
        UpdateCard.Visibility = Visibility.Visible;
        UpdateStateText.Text = $"Есть версия {latest} — кнопка «Обновить» наверху.";
    }

    /// <summary>Спросить о новой версии прямо сейчас, не дожидаясь суточной проверки.</summary>
    private async void OnCheckUpdate(object sender, RoutedEventArgs e)
    {
        CheckUpdateButton.IsEnabled = false;
        UpdateStateText.Text = "Смотрю…";
        await CheckForUpdateAsync(force: true);
        CheckUpdateButton.IsEnabled = true;
    }

    /// <summary>Скачивает архив и показывает его в проводнике.</summary>
    private async void OnInstallUpdate(object sender, RoutedEventArgs e)
    {
        if (!UpdateButton.IsEnabled) return;

        UpdateButton.IsEnabled = false;
        UpdateButton.Content = "Скачиваю…";
        var progress = new Progress<int>(percent => UpdateButton.Content = $"Скачиваю… {percent}%");

        var archive = await UpdateCheck.DownloadAsync(progress);

        UpdateButton.IsEnabled = true;
        UpdateButton.Content = "Обновить";

        if (archive is null)
        {
            UpdateHint.Text = "Скачать не удалось. Попробуйте ещё раз или скачайте вручную.";
            return;
        }

        UpdateHint.Text = $"Архив версии {_updateVersion} скачан. Закройте программу, распакуйте "
            + "его поверх текущей папки с заменой и запустите снова.";
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{archive}\"") { UseShellExecute = true });
    }

    private string _updateVersion = "";

    private static string AppVersion =>
        System.Reflection.Assembly.GetExecutingAssembly().GetName().Version is { } version
            ? $"{version.Major}.{version.Minor}.{version.Build}"
            : "0.0.0";

    /// <summary>
    /// Размер пакета. Задаётся при подключении, поэтому туннель пересобирается.
    /// </summary>
    private void OnMtuChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _store.Config.Mtu = Mtu1420.IsChecked == true ? 1420
            : Mtu1380.IsChecked == true ? 1380
            : Mtu1280.IsChecked == true ? 1280
            : 0;
        _store.Save();
        _ = ReapplyAsync();
    }

    // MARK: - Замер скорости

    /// <summary>
    /// Меряет приём и отдачу двумя путями сразу.
    ///
    /// Одно число ничего не говорит: гостевой Wi-Fi бывает медленнее любого
    /// VPN. Сравнение с прямой закачкой отвечает, виноват туннель или сеть.
    /// </summary>
    private async void OnMeasureSpeed(object sender, RoutedEventArgs e)
    {
        if (!SpeedButton.IsEnabled) return;

        SpeedButton.IsEnabled = false;
        SpeedButton.Content = "Измеряю…";
        SpeedText.Text = "";
        SpeedHint.Text = "";

        var result = await SpeedTest.MeasureAsync();

        SpeedButton.IsEnabled = true;
        SpeedButton.Content = "Замерить скорость";

        SpeedText.Text = result.HasAny
            ? $"приём:   через VPN {SpeedTest.Format(result.DownThroughTunnel)}"
              + $"   без VPN {SpeedTest.Format(result.DownDirect)}\n"
              + $"отдача:  через VPN {SpeedTest.Format(result.UpThroughTunnel)}"
              + $"   без VPN {SpeedTest.Format(result.UpDirect)}"
            : "";

        SpeedHint.Text = result.Note.Length > 0 ? result.Note
            : result.TunnelIsSlower
                ? "Туннель заметно медленнее прямой закачки. Попробуйте другой размер пакета, "
                  + "а если не поможет — дело в сервере или в этой сети."
                : result.HasAny
                    ? "Туннель не режет скорость — она такая же, как без него. Значит, упирается сама сеть."
                    : "";
    }

    /// <summary>Правки применяются сразу: поднятый туннель пересобирается.</summary>
    private async Task ReapplyAsync()
    {
        if (_tunnel.Status.State != ConnectionState.Connected || _busy) return;
        _busy = true;
        Render();
        try
        {
            await _tunnel.ConnectAsync();
        }
        finally
        {
            _busy = false;
            Render();
        }
    }

    // MARK: - Ключ

    private void OnPasteKey(object sender, RoutedEventArgs e)
    {
        if (Clipboard.ContainsImage())
        {
            var payload = ReadQrCode(Clipboard.GetImage());
            if (payload is not null)
            {
                ImportPayload(payload, "картинки из буфера");
                return;
            }
        }

        var text = Clipboard.ContainsText() ? Clipboard.GetText() : "";
        if (string.IsNullOrWhiteSpace(text))
        {
            ShowNote("В буфере обмена пусто — скопируйте ссылку vpn://, QR-код или текст настроек.", true);
            return;
        }
        ImportPayload(text, "буфера обмена");
    }

    private void OnOpenFile(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Ключ доступа",
            Filter = "Ключ или QR-код (*.conf;*.txt;*.png;*.jpg;*.jpeg;*.bmp)|*.conf;*.txt;*.png;*.jpg;*.jpeg;*.bmp|Все файлы|*.*",
            CheckFileExists = true,
        };
        if (dialog.ShowDialog(this) == true) LoadFromFile(dialog.FileName);
    }

    private void OnClearProfile(object sender, RoutedEventArgs e)
    {
        _store.ClearProfile();
        ShowNote("Ключ удалён.", false);
        Render();
    }

    private void OnDragOver(object sender, System.Windows.DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop)
            ? System.Windows.DragDropEffects.Copy
            : System.Windows.DragDropEffects.None;
        e.Handled = true;
    }

    private void OnFileDropped(object sender, System.Windows.DragEventArgs e)
    {
        if (e.Data.GetData(System.Windows.DataFormats.FileDrop) is string[] { Length: > 0 } files)
        {
            LoadFromFile(files[0]);
        }
    }

    private void LoadFromFile(string path)
    {
        var extension = Path.GetExtension(path).ToLowerInvariant();
        var isImage = extension is ".png" or ".jpg" or ".jpeg" or ".bmp" or ".gif" or ".tif" or ".tiff";

        if (isImage)
        {
            try
            {
                var image = new BitmapImage(new Uri(path));
                var payload = ReadQrCode(image);
                if (payload is null)
                {
                    ShowNote("QR-код на картинке не нашёлся. Снимок должен быть чётким и целиком.", true);
                    return;
                }
                ImportPayload(payload, $"«{Path.GetFileName(path)}»");
            }
            catch (Exception error)
            {
                ShowNote($"Картинку не удалось прочитать: {error.Message}", true);
            }
            return;
        }

        try
        {
            ImportPayload(File.ReadAllText(path), $"«{Path.GetFileName(path)}»");
        }
        catch (Exception error)
        {
            ShowNote($"Файл не удалось прочитать: {error.Message}", true);
        }
    }

    /// <summary>Общий путь для всего, чем делятся: ссылка, QR-код, файл настроек.</summary>
    private void ImportPayload(string payload, string source)
    {
        var config = SharedLink.ExtractConfig(payload);
        if (config is null)
        {
            ShowNote(SharedLink.LooksLikeLink(payload)
                ? $"{source}: это ссылка не с WireGuard — программа понимает WireGuard и AmneziaWG."
                : $"{source}: настройки WireGuard не нашлись.", true);
            return;
        }

        try
        {
            var profile = WgProfile.Parse(config);
            TunnelController.WriteTunnelConfig(profile.ToConfigText(new[] { "0.0.0.0/0" }, includeDns: true));
            ShowNote($"Ключ загружен из {source}: {profile.ProtocolName}, сервер {profile.EndpointHost}.", false);
            Render();
        }
        catch (Exception error)
        {
            ShowNote($"{source}: {error.Message}", true);
        }
    }

    private string? ReadQrCode(BitmapSource? image)
    {
        if (image is null) return null;

        var converted = new FormatConvertedBitmap(image, System.Windows.Media.PixelFormats.Bgra32, null, 0);
        var width = converted.PixelWidth;
        var height = converted.PixelHeight;
        var stride = width * 4;
        var pixels = new byte[height * stride];
        converted.CopyPixels(pixels, stride, 0);

        var source = new RGBLuminanceSource(pixels, width, height, RGBLuminanceSource.BitmapFormat.BGRA32);
        var reader = new BarcodeReaderGeneric
        {
            Options = new DecodingOptions
            {
                TryHarder = true,
                PossibleFormats = new[] { BarcodeFormat.QR_CODE },
            },
        };
        return reader.Decode(source)?.Text;
    }

    private void ShowNote(string text, bool failed)
    {
        ImportNote.Text = text;
        ImportNote.Foreground = failed
            ? (System.Windows.Media.Brush)FindResource("Danger")
            : (System.Windows.Media.Brush)FindResource("Connected");
    }

    // MARK: - Проверка адреса

    private async void OnCheckIp(object sender, RoutedEventArgs e)
    {
        CheckIpButton.IsEnabled = false;
        IpText.Text = "Проверяю…";
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
            var body = await http.GetStringAsync("https://ipinfo.io/json");
            using var json = JsonDocument.Parse(body);
            var ip = json.RootElement.TryGetProperty("ip", out var ipValue) ? ipValue.GetString() : "";
            var country = json.RootElement.TryGetProperty("country", out var countryValue) ? countryValue.GetString() : "";
            var city = json.RootElement.TryGetProperty("city", out var cityValue) ? cityValue.GetString() : "";

            IpText.Text = $"{ip} · {CountryName(country)} {city}".Trim();
            IpText.Foreground = country == "KZ"
                ? (System.Windows.Media.Brush)FindResource("Connected")
                : (System.Windows.Media.Brush)FindResource("Waiting");
        }
        catch (Exception error)
        {
            IpText.Text = $"Проверить не вышло: {error.Message}";
            IpText.Foreground = (System.Windows.Media.Brush)FindResource("Danger");
        }
        finally
        {
            CheckIpButton.IsEnabled = true;
        }
    }

    private static string CountryName(string? code) => code switch
    {
        "KZ" => "Казахстан",
        "RU" => "Россия",
        "NL" => "Нидерланды",
        "DE" => "Германия",
        "US" => "США",
        null or "" => "",
        _ => code,
    };
}
