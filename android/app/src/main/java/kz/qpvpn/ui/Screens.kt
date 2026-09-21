package kz.qpvpn.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kz.qpvpn.R
import kz.qpvpn.model.AppConfig
import kz.qpvpn.model.ConnectionState
import kz.qpvpn.model.TunnelOptions
import kz.qpvpn.model.TunnelStatus
import kz.qpvpn.model.WorkFilter

enum class Section(val title: String) {
    HOME("Главная"),
    PROFILE("Профиль"),
    SETTINGS("Ещё"),
}

data class ScreenState(
    val config: AppConfig,
    val status: TunnelStatus,
    val hasProfile: Boolean,
    val profileSummary: String,
    val profileProtocol: String,
    val ruZoneCount: Int,

    /** Программы, которым туннель не показывается вовсе. */
    val directApps: List<String>,
    val masterCount: Int,
    val masterSections: List<Pair<String, Int>>,

    /** Какая версия установлена сейчас. */
    val currentVersion: String,

    /** Разрешены ли уведомления: без них значка вверху не будет. */
    val notificationsAllowed: Boolean,
    val diagnostics: () -> String,
    val ipText: String,
    val ipIsKazakhstan: Boolean,
    val checkingIp: Boolean,

    /** Свежая версия, если она вышла; пусто — обновлять нечего. */
    val updateVersion: String,
    val updateBusy: Boolean,
    val updateNote: String,

    /** Замер скорости: строка с двумя числами и подсказка под ней. */
    val speedText: String,
    val speedHint: String,
    val measuringSpeed: Boolean,
)

data class ScreenActions(
    val onToggle: () -> Unit,

    /** Единственный переключатель программы: рабочие ресурсы. */
    val onWorkFilterChange: (Boolean) -> Unit,
    val onBackupEndpointChange: (String) -> Unit,
    val onOpenNotificationSettings: () -> Unit,
    val onPickProfile: () -> Unit,
    val onClearProfile: () -> Unit,
    val onOptionsChange: (TunnelOptions) -> Unit,
    val onCheckIp: () -> Unit,
    val onMeasureSpeed: () -> Unit,
    val onInstallUpdate: () -> Unit,
    val onCheckUpdate: () -> Unit,
    val onCopyDiagnostics: () -> Unit,
    val onScanQr: () -> Unit,
    val onPickQrImage: () -> Unit,
    val onImportText: (String) -> Unit,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QpVpnRoot(state: ScreenState, actions: ScreenActions) {
    var section by remember { mutableStateOf(Section.HOME) }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        // Развёрнутый экран складного Samsung — широкий, разделы уезжают влево.
        val wide = maxWidth >= 720.dp

        if (wide) {
            Row(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
                NavigationRail(containerColor = MaterialTheme.colorScheme.surface) {
                    Spacer(Modifier.height(12.dp))
                    Section.entries.forEach { item ->
                        NavigationRailItem(
                            selected = section == item,
                            onClick = { section = item },
                            icon = { Icon(iconFor(item), contentDescription = item.title) },
                            label = { Text(item.title) },
                        )
                    }
                }
                Box(modifier = Modifier.weight(1f)) {
                    SectionContent(section, state, actions, PaddingValues(0.dp)) { section = it }
                }
            }
        } else {
            Scaffold(
                containerColor = MaterialTheme.colorScheme.background,
                bottomBar = {
                    NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                        Section.entries.forEach { item ->
                            NavigationBarItem(
                                selected = section == item,
                                onClick = { section = item },
                                icon = { Icon(iconFor(item), contentDescription = item.title) },
                                label = { Text(item.title, style = MaterialTheme.typography.labelSmall) },
                            )
                        }
                    }
                },
            ) { padding ->
                SectionContent(section, state, actions, padding) { section = it }
            }
        }
    }
}

private fun iconFor(section: Section) = when (section) {
    Section.HOME -> Icons.Filled.Shield
    Section.PROFILE -> Icons.Filled.VpnKey
    Section.SETTINGS -> Icons.Filled.Settings
}

@Composable
private fun SectionContent(
    section: Section,
    state: ScreenState,
    actions: ScreenActions,
    padding: PaddingValues,
    onNavigate: (Section) -> Unit,
) {
    Box(modifier = Modifier.fillMaxSize().padding(bottom = padding.calculateBottomPadding())) {
        when (section) {
            Section.HOME -> HomeSection(state, actions, onNavigate)
            Section.PROFILE -> ProfileSection(state, actions)
            Section.SETTINGS -> SettingsSection(state, actions)
        }
    }
}

// MARK: - Главная

@Composable
private fun HomeSection(state: ScreenState, actions: ScreenActions, onNavigate: (Section) -> Unit) {
    val colors = LocalAppColors.current
    val status = state.status
    var whatsInside by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
    ) {
        // Шапка с градиентом
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(bottomStart = 28.dp, bottomEnd = 28.dp))
                .background(colors.heroGradient)
                .padding(horizontal = 20.dp)
                .padding(top = 28.dp, bottom = 22.dp),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                if (state.hasProfile) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Surface(color = Color.White.copy(alpha = 0.16f), shape = RoundedCornerShape(8.dp)) {
                            Text(
                                state.profileProtocol,
                                style = MaterialTheme.typography.labelSmall,
                                color = colors.onHero,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                            )
                        }
                    }
                }

                Image(
                    painter = painterResource(R.drawable.kupibas_logo),
                    contentDescription = "Kupibas",
                    contentScale = ContentScale.FillWidth,
                    modifier = Modifier.fillMaxWidth(0.66f).padding(top = 2.dp),
                )

                Spacer(Modifier.height(10.dp))

                Text(
                    "Premium VPN",
                    style = MaterialTheme.typography.headlineSmall,
                    color = colors.onHero,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    "Special for Kupibas Group",
                    style = MaterialTheme.typography.labelMedium,
                    color = colors.heroMuted,
                )

                Spacer(Modifier.height(14.dp))

                PowerButton(state = status.state, onClick = actions.onToggle)

                Text(
                    status.state.title,
                    style = MaterialTheme.typography.headlineSmall,
                    color = colors.onHero,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    if (status.serverName.isNotEmpty()) status.serverName
                    else if (state.hasProfile) "Профиль загружен" else "Профиль не загружен",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.heroMuted,
                )

                if (status.message.isNotEmpty()) {
                    Spacer(Modifier.height(6.dp))
                    Text(
                        status.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White,
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(colors.danger.copy(alpha = 0.35f))
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    )
                }

                Spacer(Modifier.height(20.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                ) {
                    HeroStat("В СЕТИ", if (status.state == ConnectionState.CONNECTED) Format.duration(status.connectedSince) else "—")
                    HeroStat("ПРИНЯТО", Format.bytes(status.rxBytes))
                    HeroStat("ОТПРАВЛЕНО", Format.bytes(status.txBytes))
                }
            }
        }

        Column(modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            if (!state.hasProfile) {
                SectionHeader("Сначала профиль", "Без него подключаться некуда")
                InfoCard {
                    Text(
                        "Загрузите файл .conf от вашего сервера — Amnezia, WireGuard или любой другой, " +
                            "который выдаёт конфигурацию WireGuard.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Button(onClick = { onNavigate(Section.PROFILE) }, modifier = Modifier.fillMaxWidth()) {
                        Text("Открыть профиль")
                    }
                }
            }

            if (!state.notificationsAllowed) {
                InfoCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Filled.Notifications,
                            contentDescription = null,
                            tint = colors.waiting,
                        )
                        Spacer(Modifier.width(12.dp))
                        Text(
                            "Разрешите уведомления — иначе значок VPN не появится наверху экрана.",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    OutlinedButton(
                        onClick = actions.onOpenNotificationSettings,
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Разрешить уведомления") }
                }
            }

            if (state.updateVersion.isNotEmpty()) {
                InfoCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Filled.Download,
                            contentDescription = null,
                            tint = colors.connected,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Вышла версия ${state.updateVersion}", style = MaterialTheme.typography.titleMedium)
                            Text(
                                "Установлена ${state.currentVersion}. Скачается сюда же, " +
                                    "ключ и настройки останутся на месте.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    if (state.updateNote.isNotEmpty()) {
                        Text(
                            state.updateNote,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Button(
                        onClick = actions.onInstallUpdate,
                        enabled = !state.updateBusy,
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(if (state.updateBusy) "Обновляю…" else "Обновить") }
                }
            }

            SectionHeader("Как идёт трафик", "Настраивать ничего не нужно")
            InfoCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.Shield,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Заблокированные сервисы", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Идут через VPN, казахстанский адрес",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                    Icon(
                        Icons.Filled.Home,
                        contentDescription = null,
                        tint = colors.connected,
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Российские сайты", style = MaterialTheme.typography.titleMedium)
                        Text(
                            if (state.ruZoneCount > 0)
                                "МАХ, госуслуги, банки, маркетплейсы — напрямую (${state.ruZoneCount} " +
                                    plural(state.ruZoneCount, "подсеть", "подсети", "подсетей") + " России)"
                            else
                                "МАХ, госуслуги, банки, маркетплейсы — напрямую",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                if (status.routeCount > 0) {
                    KeyValueRow("Маршрутов в туннеле", status.routeCount.toString())
                }

                if (state.directApps.isNotEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                        Icon(
                            Icons.Filled.PhoneAndroid,
                            contentDescription = null,
                            tint = colors.connected,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Мимо VPN целиком", style = MaterialTheme.typography.titleMedium)
                            Text(
                                if (state.directApps.size <= 6) state.directApps.joinToString(", ")
                                else state.directApps.take(6).joinToString(", ") +
                                    " и ещё ${state.directApps.size - 6}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "Российские программы: туннель им не нужен, а некоторые — МАХ, " +
                                    "банки, госуслуги — при включённом VPN просто отказываются работать. " +
                                    "Для них его как будто нет.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                TextButton(onClick = { whatsInside = !whatsInside }) {
                    Text(if (whatsInside) "Свернуть список" else "Что работает через VPN")
                }

                if (whatsInside) {
                    state.masterSections.forEach { section ->
                        Row(modifier = Modifier.fillMaxWidth()) {
                            Text(
                                section.first,
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                section.second.toString(),
                                style = MaterialTheme.typography.bodyMedium,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    Text(
                        "Это примеры — адреса не перечисляются по именам: через VPN уходит всё, " +
                            "кроме российских подсетей, поэтому работает и то, чего в списке нет.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            SectionHeader("Рабочие ресурсы")
            WorkFilterCard(state, actions)

            SectionHeader("Скорость", "Через VPN и без него — на одной и той же закачке")
            InfoCard {
                if (state.speedText.isNotEmpty()) {
                    Text(
                        state.speedText,
                        style = MaterialTheme.typography.titleMedium,
                        fontFamily = FontFamily.Monospace,
                    )
                }
                if (state.speedHint.isNotEmpty()) {
                    Text(
                        state.speedHint,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                OutlinedButton(
                    onClick = actions.onMeasureSpeed,
                    enabled = !state.measuringSpeed,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (state.measuringSpeed) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(10.dp))
                        Text("Измеряю…")
                    } else {
                        Icon(Icons.Filled.Speed, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Замерить скорость")
                    }
                }

                // Размер пакета — единственное, чем скорость лечится со
                // стороны телефона, поэтому он здесь же, а не в настройках.
                Text(
                    "Размер пакета (MTU). В гостевых и мобильных сетях большие пакеты часто " +
                        "не проходят целиком: сообщения уходят, а видео крутится и не качается. " +
                        "На «Авто» приложение подбирает размер само при подключении.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(0 to "Авто", 1420 to "1420", 1380 to "1380", 1280 to "1280")
                        .forEach { (value, title) ->
                            FilterChip(
                                selected = state.config.options.mtu == value,
                                onClick = { actions.onOptionsChange(state.config.options.copy(mtu = value)) },
                                label = { Text(title) },
                            )
                        }
                }
            }

            SectionHeader("Проверка")
            InfoCard {
                Text(
                    "Посмотрите, из какой страны вас видят сайты.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                if (state.ipText.isNotEmpty()) {
                    Text(
                        state.ipText,
                        style = MaterialTheme.typography.titleMedium,
                        fontFamily = FontFamily.Monospace,
                        color = if (state.ipIsKazakhstan) colors.connected else MaterialTheme.colorScheme.onSurface,
                    )
                }
                OutlinedButton(
                    onClick = actions.onCheckIp,
                    enabled = !state.checkingIp,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (state.checkingIp) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(10.dp))
                        Text("Проверяю…")
                    } else {
                        Icon(Icons.Filled.Public, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Проверить мой IP")
                    }
                }
            }
        }
    }
}

/**
 * Единственный переключатель программы.
 *
 * Всё остальное зашито: заблокированные сервисы идут через VPN, российские
 * адреса — напрямую. Рабочие ресурсы человек выбирает сам, потому что они
 * лежат на российском адресе и смотреть на них можно и так, и через сервер.
 */
@Composable
private fun WorkFilterCard(state: ScreenState, actions: ScreenActions) {
    val colors = LocalAppColors.current

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (state.config.workFilter) MaterialTheme.colorScheme.secondaryContainer
            else MaterialTheme.colorScheme.surface
        ),
        border = BorderStroke(
            if (state.config.workFilter) 1.5.dp else 1.dp,
            if (state.config.workFilter) MaterialTheme.colorScheme.secondary else colors.cardBorder,
        ),
        shape = RoundedCornerShape(18.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Рабочие ресурсы", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "${WorkFilter.count} ${plural(WorkFilter.count, "адрес", "адреса", "адресов")} · заложены в приложение",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.width(10.dp))
                Switch(
                    checked = state.config.workFilter,
                    onCheckedChange = { actions.onWorkFilterChange(it) },
                )
            }

            Text(
                if (state.config.workFilter)
                    "Включён: эти ресурсы идут через VPN — даже если всё остальное идёт напрямую."
                else
                    "Выключен: эти ресурсы идут напрямую, с домашнего адреса.",
                style = MaterialTheme.typography.bodyMedium,
                color = if (state.config.workFilter) MaterialTheme.colorScheme.onSecondaryContainer
                else MaterialTheme.colorScheme.onSurfaceVariant,
            )

            WorkFilter.resources.forEach { resource ->
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        resource.title,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.width(72.dp),
                    )
                    Text(
                        resource.url,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

// MARK: - Профиль

@Composable
private fun ProfileSection(state: ScreenState, actions: ScreenActions) {
    var showLinkDialog by remember { mutableStateOf(false) }
    var linkText by remember { mutableStateOf("") }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SectionHeader("Профиль подключения")

        InfoCard {
            if (state.hasProfile) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.VpnKey,
                        contentDescription = null,
                        tint = LocalAppColors.current.connected,
                    )
                    Spacer(Modifier.width(10.dp))
                    Text("Профиль загружен", style = MaterialTheme.typography.titleMedium)
                }
                Text(
                    state.profileSummary,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Text("Профиль не загружен", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Подойдёт файл .conf из Amnezia, от вашего сервера WireGuard или от провайдера VPN.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Button(onClick = actions.onScanQr, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Filled.QrCodeScanner, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Сканировать QR из Amnezia")
        }

        OutlinedButton(onClick = actions.onPickQrImage, modifier = Modifier.fillMaxWidth()) {
            Text("QR со снимка экрана")
        }

        OutlinedButton(onClick = { showLinkDialog = true }, modifier = Modifier.fillMaxWidth()) {
            Text("Вставить ссылку vpn://")
        }

        OutlinedButton(onClick = actions.onPickProfile, modifier = Modifier.fillMaxWidth()) {
            Text("Выбрать файл .conf")
        }

        BackupEntryCard(state, actions)

        if (state.hasProfile) {
            TextButton(onClick = actions.onClearProfile, modifier = Modifier.fillMaxWidth()) {
                Text("Удалить профиль")
            }
        }

        InfoCard {
            Text("Как поделиться из Amnezia", style = MaterialTheme.typography.titleMedium)
            Text(
                "Откройте Amnezia → нужный сервер → «Поделиться» → выберите протокол AmneziaWG " +
                    "или WireGuard. Дальше любой способ на выбор:",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "• если Amnezia на другом телефоне — «Сканировать QR»;\n" +
                    "• если на этом же — сделайте снимок экрана с кодом и нажмите «QR со снимка»;\n" +
                    "• либо скопируйте ссылку и нажмите «Вставить ссылку»;\n" +
                    "• либо из Amnezia нажмите «Поделиться» и выберите QP VPN в списке программ.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "Маскировка AmneziaWG поддерживается: мусорные пакеты и подменённые заголовки " +
                    "переносятся в туннель как есть.",
                style = MaterialTheme.typography.bodySmall,
                color = LocalAppColors.current.connected,
            )
        }

        if (showLinkDialog) {
            AlertDialog(
                onDismissRequest = { showLinkDialog = false },
                title = { Text("Ссылка из Amnezia") },
                text = {
                    Column {
                        Text(
                            "Вставьте ссылку vpn://… или сам текст настроек.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(Modifier.height(8.dp))
                        OutlinedTextField(
                            value = linkText,
                            onValueChange = { linkText = it },
                            placeholder = { Text("vpn://…") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                },
                confirmButton = {
                    TextButton(onClick = {
                        actions.onImportText(linkText)
                        linkText = ""
                        showLinkDialog = false
                    }) { Text("Загрузить") }
                },
                dismissButton = {
                    TextButton(onClick = { showLinkDialog = false }) { Text("Отмена") }
                },
            )
        }

        Text(
            "Ключи хранятся в памяти приложения и недоступны другим программам.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Запасной вход — узел, который пересылает пакеты на сервер.
 *
 * Бывают сети, где наружу выпускают не все адреса: до сервера напрямую не
 * достучаться, а до такого узла — да. Ключ при этом тот же самый: узел
 * ничего не расшифровывает, только перебрасывает.
 */
@Composable
private fun BackupEntryCard(state: ScreenState, actions: ScreenActions) {
    var value by remember(state.config.backupEndpoint) {
        mutableStateOf(state.config.backupEndpoint)
    }

    InfoCard {
        Text("Запасной вход", style = MaterialTheme.typography.titleMedium)
        Text(
            "Необязательно. Адрес узла-пересыльщика в виде адрес:порт. " +
                "Приложение попробует сервер напрямую, а если он не ответит — этот узел.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = value,
            onValueChange = {
                value = it
                actions.onBackupEndpointChange(it)
            },
            singleLine = true,
            placeholder = { Text("95.213.0.1:31984") },
            modifier = Modifier.fillMaxWidth(),
        )
        if (state.config.backupEndpoint.isNotEmpty()) {
            Text(
                "Сохранён. Он вступит в дело только если сервер не ответит за двенадцать секунд.",
                style = MaterialTheme.typography.bodySmall,
                color = LocalAppColors.current.connected,
            )
        }
    }
}

// MARK: - Настройки

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsSection(state: ScreenState, actions: ScreenActions) {
    val options = state.config.options
    var showDiagnostics by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        SectionHeader("Настройки")

        InfoCard {
            Text("Размер пакета (MTU)", style = MaterialTheme.typography.titleMedium)
            Text(
                "От него зависит скорость. Чем больше — тем быстрее, но если сеть " +
                    "не пропускает такие пакеты, видео и потоковые ответы встают. " +
                    "На «Авто» приложение подбирает размер само при подключении.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                modifier = Modifier.padding(top = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                listOf(0 to "Авто", 1420 to "1420", 1380 to "1380", 1280 to "1280").forEach { (value, title) ->
                    FilterChip(
                        selected = options.mtu == value,
                        onClick = { actions.onOptionsChange(options.copy(mtu = value)) },
                        label = { Text(title) },
                    )
                }
            }
            Text(
                "При смене туннель переподнимется сам — связь пропадёт на секунду.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        InfoCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Диагностика", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Что происходит с туннелем прямо сейчас",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(onClick = { showDiagnostics = !showDiagnostics }) {
                    Text(if (showDiagnostics) "Свернуть" else "Показать")
                }
            }

            if (showDiagnostics) {
                Text(
                    remember(state.status) { state.diagnostics() },
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedButton(
                    onClick = actions.onCopyDiagnostics,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Скопировать отчёт") }
                Text(
                    "Отчёт можно переслать тому, кто выдал ключ: в нём нет самих ключей, только состояние.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        InfoCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Обновление", style = MaterialTheme.typography.titleMedium)
                    Text(
                        if (state.updateVersion.isNotEmpty())
                            "Вышла версия ${state.updateVersion}, установлена ${state.currentVersion}"
                        else
                            "Установлена версия ${state.currentVersion}. Проверяется раз в сутки.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(onClick = actions.onCheckUpdate) { Text("Проверить") }
            }
            if (state.updateNote.isNotEmpty()) {
                Text(
                    state.updateNote,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (state.updateVersion.isNotEmpty()) {
                OutlinedButton(
                    onClick = actions.onInstallUpdate,
                    enabled = !state.updateBusy,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(if (state.updateBusy) "Обновляю…" else "Обновить до ${state.updateVersion}") }
            }
        }

        InfoCard {
            Text("О программе", style = MaterialTheme.typography.titleMedium)
            KeyValueRow("Протокол", "AmneziaWG и WireGuard")
            KeyValueRow("Подсетей России", state.ruZoneCount.toString())
            KeyValueRow("Сервисов в списке", state.masterCount.toString())
            Text(
                "Маршрутизация зашита: через VPN идёт всё, кроме российских адресов. " +
                    "Настраивать её не нужно и негде.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
