package kz.qpvpn.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AltRoute
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.CallSplit
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kz.qpvpn.R
import kz.qpvpn.model.AppConfig
import kz.qpvpn.model.AppsMode
import kz.qpvpn.model.MasterFilter
import kz.qpvpn.model.ConnectionState
import kz.qpvpn.model.PresetDirection
import kz.qpvpn.model.Presets
import kz.qpvpn.model.RoutingRule
import kz.qpvpn.model.RuleKind
import kz.qpvpn.model.RulePreset
import kz.qpvpn.model.TunnelMode
import kz.qpvpn.model.TunnelOptions
import kz.qpvpn.model.TunnelStatus
import kz.qpvpn.model.WorkFilter

data class AppEntry(val packageName: String, val label: String, val icon: ImageBitmap?)

enum class Section(val title: String) {
    HOME("Главная"),
    ROUTES("Маршруты"),
    APPS("Программы"),
    PROFILE("Профиль"),
    SETTINGS("Ещё"),
}

data class ScreenState(
    val config: AppConfig,
    val status: TunnelStatus,
    val hasProfile: Boolean,
    val profileSummary: String,
    val profileProtocol: String,
    val apps: List<AppEntry>,
    val ruZoneCount: Int,
    val masterCount: Int,
    val masterSections: List<Pair<String, Int>>,
    val masterApps: Int,
    val ipText: String,
    val ipIsKazakhstan: Boolean,
    val checkingIp: Boolean,
)

data class ScreenActions(
    val onToggle: () -> Unit,
    val onModeChange: (TunnelMode) -> Unit,
    val onMainFilterChange: (Boolean) -> Unit,
    val onWorkFilterChange: (Boolean) -> Unit,
    val onAddRule: (RuleKind, String) -> String?,
    val onToggleRule: (String, Boolean) -> Unit,
    val onDeleteRule: (String) -> Unit,
    val onAddPreset: (RulePreset) -> Unit,
    val onAppsModeChange: (AppsMode) -> Unit,
    val onToggleApp: (String, Boolean) -> Unit,
    val onPickProfile: () -> Unit,
    val onClearProfile: () -> Unit,
    val onOptionsChange: (TunnelOptions) -> Unit,
    val onCheckIp: () -> Unit,
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
    Section.ROUTES -> Icons.Filled.AltRoute
    Section.APPS -> Icons.Filled.Apps
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
            Section.ROUTES -> RoutesSection(state, actions)
            Section.APPS -> AppsSection(state, actions)
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

            SectionHeader("Маршрутизация")
            InfoCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.CallSplit,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            if (state.config.mainFilter) "Обход блокировок" else state.config.mode.title,
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(
                            if (state.config.mainFilter)
                                "${state.masterCount} сервисов через VPN, остальное напрямую"
                            else
                                state.config.mode.subtitle,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = state.config.mainFilter,
                        onCheckedChange = { actions.onMainFilterChange(it) },
                    )
                }
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                    Icon(
                        Icons.Filled.Work,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.secondary,
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Рабочие ресурсы", style = MaterialTheme.typography.titleMedium)
                        Text(
                            if (state.config.workFilter) "Идут через VPN" else "Идут напрямую",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Switch(
                        checked = state.config.workFilter,
                        onCheckedChange = { actions.onWorkFilterChange(it) },
                    )
                }
                if (state.config.effectiveMode != TunnelMode.FULL) {
                    if (!state.config.mainFilter) {
                        KeyValueRow("Активных правил", state.config.activeRules.size.toString())
                    }
                    KeyValueRow("Маршрутов в туннеле", status.routeCount.toString())
                }
                if (state.config.appsMode != AppsMode.OFF) {
                    KeyValueRow("Программ выбрано", state.config.selectedApps.size.toString())
                }
                TextButton(onClick = { onNavigate(Section.ROUTES) }) { Text("Настроить маршруты") }
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

// MARK: - Маршруты

@Composable
private fun RoutesSection(state: ScreenState, actions: ScreenActions) {
    var newKind by remember { mutableStateOf(RuleKind.DOMAIN) }
    var newValue by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var kindMenu by remember { mutableStateOf(false) }
    var advanced by remember { mutableStateOf(false) }
    var whatsInside by remember { mutableStateOf(false) }

    val existing = remember(state.config.rules) {
        state.config.rules.map { "${it.kind}:${it.value.lowercase()}" }.toSet()
    }
    val colors = LocalAppColors.current

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // ——— Главный фильтр ———
        item {
            SectionHeader("Главное", "Один переключатель на все заблокированные сервисы")

            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = if (state.config.mainFilter) MaterialTheme.colorScheme.primaryContainer
                    else MaterialTheme.colorScheme.surface
                ),
                border = BorderStroke(
                    if (state.config.mainFilter) 1.5.dp else 1.dp,
                    if (state.config.mainFilter) MaterialTheme.colorScheme.primary else colors.cardBorder,
                ),
                shape = RoundedCornerShape(18.dp),
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Обход блокировок", style = MaterialTheme.typography.titleLarge)
                            Text(
                                "${state.masterCount} ${plural(state.masterCount, "сервис", "сервиса", "сервисов")} · " +
                                    "нейросети, соцсети, мессенджеры, видео, работа",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Spacer(Modifier.width(10.dp))
                        Switch(
                            checked = state.config.mainFilter,
                            onCheckedChange = { actions.onMainFilterChange(it) },
                        )
                    }

                    Text(
                        if (state.config.mainFilter)
                            "Через VPN идут только эти сервисы. Всё остальное — банки, госуслуги, маркетплейсы, любой российский сайт — работает напрямую, как без VPN."
                        else
                            "Выключен: маршруты задаются вручную в расширенных настройках.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (state.config.mainFilter) MaterialTheme.colorScheme.onPrimaryContainer
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    TextButton(onClick = { whatsInside = !whatsInside }) {
                        Text(if (whatsInside) "Свернуть список" else "Что внутри")
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
                        Spacer(Modifier.height(2.dp))
                        Row(modifier = Modifier.fillMaxWidth()) {
                            Text(
                                "Программы",
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                state.masterApps.toString(),
                                style = MaterialTheme.typography.bodyMedium,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            "Если вы включите разбор по программам в расширенных настройках, " +
                                "эти ${state.masterApps} приложений уже отмечены — отмечать вручную ничего не нужно.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // ——— Рабочие ресурсы ———
        item {
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

        // ——— Расширенные настройки ———
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .clickable { advanced = !advanced }
                    .padding(vertical = 14.dp, horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Filled.Settings,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text("Расширенные настройки", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Режимы, зона .ru, свои правила и наборы",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    if (advanced) "▲" else "▼",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        if (advanced) {
            item {
                if (state.config.mainFilter) {
                    Text(
                        "Главный фильтр включён — он задаёт маршруты сам. Настройки ниже начнут действовать, когда вы его выключите.",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.waiting,
                    )
                }
            }

            item {
                SectionHeader("Режим маршрутизации")
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ModeCard(
                        selected = state.config.mode == TunnelMode.FULL,
                        icon = Icons.Filled.Shield,
                        title = TunnelMode.FULL.title,
                        subtitle = TunnelMode.FULL.subtitle,
                        onClick = { actions.onModeChange(TunnelMode.FULL) },
                    )
                    ModeCard(
                        selected = state.config.mode == TunnelMode.INCLUDE,
                        icon = Icons.Filled.CallSplit,
                        title = TunnelMode.INCLUDE.title,
                        subtitle = TunnelMode.INCLUDE.subtitle,
                        onClick = { actions.onModeChange(TunnelMode.INCLUDE) },
                    )
                    ModeCard(
                        selected = state.config.mode == TunnelMode.EXCLUDE,
                        icon = Icons.Filled.AltRoute,
                        title = TunnelMode.EXCLUDE.title,
                        subtitle = TunnelMode.EXCLUDE.subtitle,
                        onClick = { actions.onModeChange(TunnelMode.EXCLUDE) },
                    )
                }
            }

            item {
                SectionHeader("Российская зона", "Встроенный список адресов России")
                RuZoneCard(state, actions)
            }

            item {
                SectionHeader("Наборы для прямого канала", "Пригодятся в режиме «всё через VPN, кроме правил»")
            }

            items(Presets.direct, key = { "d-" + it.id }) { preset ->
                PresetCard(
                    title = preset.title,
                    subtitle = preset.subtitle,
                    count = preset.count,
                    directionLabel = preset.direction.title,
                    throughVpn = false,
                    added = preset.values.all { "${it.first}:${it.second.lowercase()}" in existing },
                    onAdd = { actions.onAddPreset(preset) },
                )
            }

            item {
                SectionHeader("Своё правило", "Домен или подсеть")
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box {
                        OutlinedButton(onClick = { kindMenu = true }) { Text(newKind.title) }
                        DropdownMenu(expanded = kindMenu, onDismissRequest = { kindMenu = false }) {
                            RuleKind.entries.forEach { kind ->
                                DropdownMenuItem(text = { Text(kind.title) }, onClick = {
                                    newKind = kind
                                    kindMenu = false
                                })
                            }
                        }
                    }
                    OutlinedTextField(
                        value = newValue,
                        onValueChange = { newValue = it },
                        singleLine = true,
                        placeholder = { Text(if (newKind == RuleKind.DOMAIN) "kaspi.kz" else "92.46.0.0/16") },
                        modifier = Modifier.weight(1f),
                    )
                    Button(onClick = {
                        error = actions.onAddRule(newKind, newValue)
                        if (error == null) newValue = ""
                    }) { Text("+") }
                }
                error?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }

            if (state.config.rules.isNotEmpty()) {
                item {
                    SectionHeader(
                        "Свои правила",
                        "${state.config.rules.size} ${plural(state.config.rules.size, "штука", "штуки", "штук")}",
                    )
                }
                items(state.config.rules, key = { it.id }) { rule ->
                    RuleRow(rule, state.config.mode, actions)
                }
            }
        }
    }
}

/** Переключатель «вся российская зона мимо VPN» с пояснением про режим. */
@Composable
private fun RuZoneCard(state: ScreenState, actions: ScreenActions) {
    val options = state.config.options
    val active = options.bypassRuZone && state.config.mode == TunnelMode.EXCLUDE

    InfoCard {
        SwitchRow(
            title = "Вся зона .ru — мимо VPN",
            subtitle = if (state.ruZoneCount > 0)
                "${state.ruZoneCount} ${plural(state.ruZoneCount, "подсеть", "подсети", "подсетей")} России идут напрямую"
            else
                "Российские адреса идут напрямую, без единого правила",
            checked = options.bypassRuZone,
            onChange = { actions.onOptionsChange(options.copy(bypassRuZone = it)) },
        )

        if (options.bypassRuZone && state.config.mode != TunnelMode.EXCLUDE) {
            Text(
                "Работает в режиме «всё через VPN, кроме правил» — сейчас выбран другой.",
                style = MaterialTheme.typography.bodySmall,
                color = LocalAppColors.current.waiting,
            )
            TextButton(onClick = { actions.onModeChange(TunnelMode.EXCLUDE) }) {
                Text("Включить этот режим")
            }
        }

        if (active) {
            Text(
                "Банки, госуслуги, маркетплейсы и всё остальное с российскими адресами " +
                    "видят ваш домашний адрес. Остальной интернет идёт через сервер.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun RuleRow(rule: RoutingRule, mode: TunnelMode, actions: ScreenActions) {
    val colors = LocalAppColors.current
    val destination = when (mode) {
        TunnelMode.FULL -> "не используется" to MaterialTheme.colorScheme.onSurfaceVariant
        TunnelMode.INCLUDE -> "через VPN" to MaterialTheme.colorScheme.primary
        TunnelMode.EXCLUDE -> "напрямую" to colors.waiting
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (rule.kind == RuleKind.DOMAIN) Icons.Filled.Language else Icons.Filled.AltRoute,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp),
        )
        Spacer(Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                rule.value,
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
                color = if (rule.enabled) MaterialTheme.colorScheme.onSurface
                else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                if (rule.note.isEmpty()) destination.first else "${destination.first} · ${rule.note}",
                style = MaterialTheme.typography.labelSmall,
                color = destination.second,
            )
        }
        Switch(
            checked = rule.enabled,
            onCheckedChange = { actions.onToggleRule(rule.id, it) },
        )
        IconButton(onClick = { actions.onDeleteRule(rule.id) }) {
            Icon(Icons.Filled.Delete, contentDescription = "Удалить", modifier = Modifier.size(18.dp))
        }
    }
}

// MARK: - Программы

@Composable
private fun AppsSection(state: ScreenState, actions: ScreenActions) {
    var query by remember { mutableStateOf("") }

    val visible = remember(query, state.apps) {
        if (query.isBlank()) state.apps
        else state.apps.filter { it.label.contains(query, ignoreCase = true) }
    }

    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        SectionHeader(
            "Маршруты по программам",
            "Чего нет на компьютере: правила прямо для приложений",
        )

        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            AppsMode.entries.forEach { mode ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { actions.onAppsModeChange(mode) },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = state.config.appsMode == mode,
                        onClick = { actions.onAppsModeChange(mode) },
                    )
                    Text(mode.title, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }

        if (state.config.mainFilter && state.config.appsMode == AppsMode.ONLY_SELECTED) {
            val covered = remember(state.apps) {
                state.apps.count { it.packageName in MasterFilter.packages }
            }
            Text(
                "Главный фильтр уже добавил $covered ${plural(covered, "программу", "программы", "программ")} " +
                    "из встроенного списка — отмечать их вручную не нужно.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(top = 8.dp),
            )
        }

        if (state.config.appsMode != AppsMode.OFF) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                singleLine = true,
                placeholder = { Text("Поиск программы") },
                modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
            )

            Text(
                "Выбрано: ${state.config.selectedApps.size}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(visible, key = { it.packageName }) { app ->
                    val selected = app.packageName in state.config.selectedApps
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .clickable { actions.onToggleApp(app.packageName, !selected) }
                            .padding(horizontal = 8.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (app.icon != null) {
                            Image(
                                bitmap = app.icon,
                                contentDescription = null,
                                modifier = Modifier.size(38.dp).clip(RoundedCornerShape(10.dp)),
                            )
                        } else {
                            Box(
                                modifier = Modifier
                                    .size(38.dp)
                                    .clip(CircleShape)
                                    .background(MaterialTheme.colorScheme.surfaceVariant),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(app.label.take(1).uppercase(), style = MaterialTheme.typography.titleMedium)
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(app.label, style = MaterialTheme.typography.bodyLarge)
                            Text(
                                app.packageName,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = selected,
                            onCheckedChange = { actions.onToggleApp(app.packageName, it) },
                        )
                    }
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

// MARK: - Настройки

@Composable
private fun SettingsSection(state: ScreenState, actions: ScreenActions) {
    val options = state.config.options

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        SectionHeader("Настройки")

        InfoCard {
            SwitchRow(
                title = "DNS-серверы из профиля",
                subtitle = "В режиме «только правила» системный DNS не трогается",
                checked = options.useTunnelDns,
                onChange = { actions.onOptionsChange(options.copy(useTunnelDns = it)) },
            )
            SwitchRow(
                title = "Вся зона .ru мимо VPN",
                subtitle = "Российские адреса идут напрямую в режиме «всё кроме правил»",
                checked = options.bypassRuZone,
                onChange = { actions.onOptionsChange(options.copy(bypassRuZone = it)) },
            )
            SwitchRow(
                title = "Заворачивать IPv6 в туннель",
                subtitle = "Иначе сайты могут увидеть настоящий адрес по IPv6",
                checked = options.blockIpv6,
                onChange = { actions.onOptionsChange(options.copy(blockIpv6 = it)) },
            )
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Пересчёт адресов доменов", style = MaterialTheme.typography.bodyLarge)
                    Text(
                        "каждые ${options.reresolveMinutes} мин",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                OutlinedButton(onClick = {
                    actions.onOptionsChange(
                        options.copy(reresolveMinutes = (options.reresolveMinutes - 1).coerceAtLeast(1))
                    )
                }) { Text("−") }
                Spacer(Modifier.width(8.dp))
                OutlinedButton(onClick = {
                    actions.onOptionsChange(
                        options.copy(reresolveMinutes = (options.reresolveMinutes + 1).coerceAtMost(60))
                    )
                }) { Text("+") }
            }
        }

        InfoCard {
            Text("О программе", style = MaterialTheme.typography.titleMedium)
            KeyValueRow("Протокол", "WireGuard")
            KeyValueRow("Правил в наборах", Presets.all.sumOf { it.count }.toString())
            KeyValueRow("Подсетей России", state.ruZoneCount.toString())
            Text(
                "Маршруты считаются по адресам назначения, а списки программ — средствами Android.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
