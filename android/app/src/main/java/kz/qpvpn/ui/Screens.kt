package kz.qpvpn.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AltRoute
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Power
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.BoxWithConstraints
import kz.qpvpn.model.AppConfig
import kz.qpvpn.model.AppsMode
import kz.qpvpn.model.ConnectionState
import kz.qpvpn.model.Presets
import kz.qpvpn.model.RuleKind
import kz.qpvpn.model.RulePreset
import kz.qpvpn.model.RoutingRule
import kz.qpvpn.model.TunnelMode
import kz.qpvpn.model.TunnelOptions
import kz.qpvpn.model.TunnelStatus

/** Программа, установленная на телефоне. */
data class AppEntry(val packageName: String, val label: String)

enum class Section(val title: String) {
    HOME("Главная"),
    ROUTES("Маршруты"),
    APPS("Программы"),
    PROFILE("Профиль"),
    SETTINGS("Настройки"),
}

/** Всё состояние приходит сверху — экран ничего не хранит сам, кроме ввода. */
data class ScreenState(
    val config: AppConfig,
    val status: TunnelStatus,
    val hasProfile: Boolean,
    val profileSummary: String,
    val apps: List<AppEntry>,
    val ipText: String,
    val ipIsKazakhstan: Boolean,
    val checkingIp: Boolean,
)

data class ScreenActions(
    val onToggle: () -> Unit,
    val onModeChange: (TunnelMode) -> Unit,
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
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QpVpnRoot(state: ScreenState, actions: ScreenActions) {
    var section by remember { mutableStateOf(Section.HOME) }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        // Разложенный экран Samsung — широкий: панель разделов уезжает влево,
        // как в планшетном режиме One UI.
        val wide = maxWidth >= 720.dp

        if (wide) {
            Row(modifier = Modifier.fillMaxSize()) {
                NavigationRail {
                    Section.entries.forEach { item ->
                        NavigationRailItem(
                            selected = section == item,
                            onClick = { section = item },
                            icon = { Icon(iconFor(item), contentDescription = item.title) },
                            label = { Text(item.title) },
                        )
                    }
                }
                Surface(modifier = Modifier.fillMaxSize()) {
                    SectionContent(section, state, actions, PaddingValues(20.dp))
                }
            }
        } else {
            Scaffold(
                bottomBar = {
                    NavigationBar {
                        Section.entries.forEach { item ->
                            NavigationBarItem(
                                selected = section == item,
                                onClick = { section = item },
                                icon = { Icon(iconFor(item), contentDescription = item.title) },
                                label = { Text(item.title, style = MaterialTheme.typography.labelSmall) },
                            )
                        }
                    }
                }
            ) { padding ->
                SectionContent(section, state, actions, padding)
            }
        }
    }
}

private fun iconFor(section: Section) = when (section) {
    Section.HOME -> Icons.Filled.Power
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
) {
    Box(modifier = Modifier.padding(padding)) {
        when (section) {
            Section.HOME -> HomeSection(state, actions)
            Section.ROUTES -> RoutesSection(state, actions)
            Section.APPS -> AppsSection(state, actions)
            Section.PROFILE -> ProfileSection(state, actions)
            Section.SETTINGS -> SettingsSection(state, actions)
        }
    }
}

// MARK: - Главная

@Composable
private fun HomeSection(state: ScreenState, actions: ScreenActions) {
    val status = state.status

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (!state.hasProfile) {
            WarningCard("Профиль не загружен. Откройте раздел «Профиль» и выберите файл .conf от вашего сервера.")
        }

        Spacer(Modifier.height(8.dp))

        val accent = when (status.state) {
            ConnectionState.CONNECTED -> Color(0xFF2E9E6B)
            ConnectionState.CONNECTING -> Color(0xFFCB8B1A)
            ConnectionState.ERROR -> MaterialTheme.colorScheme.error
            ConnectionState.DISCONNECTED -> MaterialTheme.colorScheme.outline
        }

        Box(
            modifier = Modifier
                .size(148.dp)
                .clip(CircleShape)
                .background(accent.copy(alpha = 0.14f))
                .clickable { actions.onToggle() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.Power,
                contentDescription = if (status.state == ConnectionState.DISCONNECTED) "Включить" else "Выключить",
                tint = accent,
                modifier = Modifier.size(64.dp),
            )
        }

        Text(status.state.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)

        if (status.message.isNotEmpty()) {
            Text(
                status.message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
        }

        Text(state.config.mode.title, style = MaterialTheme.typography.bodyMedium)

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                InfoRow("Сервер", status.serverName.ifEmpty { "—" })
                InfoRow("Время сессии", if (status.state == ConnectionState.CONNECTED) Format.duration(status.connectedSince) else "—")
                InfoRow("Принято", Format.bytes(status.rxBytes))
                InfoRow("Отправлено", Format.bytes(status.txBytes))
                if (state.config.mode != TunnelMode.FULL) {
                    InfoRow("Маршрутов", status.routeCount.toString())
                }
            }
        }

        OutlinedButton(onClick = actions.onCheckIp, enabled = !state.checkingIp) {
            if (state.checkingIp) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
                Text("Проверяю…")
            } else {
                Icon(Icons.Filled.Public, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Проверить мой IP")
            }
        }

        if (state.ipText.isNotEmpty()) {
            Text(
                state.ipText,
                style = MaterialTheme.typography.bodyLarge,
                color = if (state.ipIsKazakhstan) Color(0xFF2E9E6B) else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

// MARK: - Маршруты

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RoutesSection(state: ScreenState, actions: ScreenActions) {
    var newKind by remember { mutableStateOf(RuleKind.DOMAIN) }
    var newValue by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var kindMenu by remember { mutableStateOf(false) }
    var presetMenu by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        Text("Что идёт через VPN", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(vertical = 12.dp))

        TunnelMode.entries.forEach { mode ->
            ChoiceRow(
                selected = state.config.mode == mode,
                title = mode.title,
                subtitle = mode.subtitle,
                onClick = { actions.onModeChange(mode) },
            )
        }

        Spacer(Modifier.height(12.dp))

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
            }) { Text("＋") }
        }

        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }

        Box {
            TextButton(onClick = { presetMenu = true }) { Text("Готовые наборы") }
            DropdownMenu(expanded = presetMenu, onDismissRequest = { presetMenu = false }) {
                Presets.all.forEach { preset ->
                    DropdownMenuItem(
                        text = { Text("${preset.title} — ${preset.mode.title.lowercase()}") },
                        onClick = {
                            actions.onAddPreset(preset)
                            presetMenu = false
                        },
                    )
                }
            }
        }

        if (state.config.rules.isEmpty()) {
            Text(
                if (state.config.mode == TunnelMode.INCLUDE)
                    "Правил нет — значит, в туннель сейчас ничего не уходит."
                else
                    "Правил нет — весь трафик идёт через VPN.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 24.dp),
            )
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                items(state.config.rules, key = { it.id }) { rule ->
                    RuleRow(rule, state.config.mode, actions)
                }
            }
        }
    }
}

@Composable
private fun RuleRow(rule: RoutingRule, mode: TunnelMode, actions: ScreenActions) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Switch(checked = rule.enabled, onCheckedChange = { actions.onToggleRule(rule.id, it) })
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(rule.value, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodyMedium)
                val destination = when (mode) {
                    TunnelMode.FULL -> "не используется"
                    TunnelMode.INCLUDE -> "через VPN"
                    TunnelMode.EXCLUDE -> "напрямую"
                }
                Text(
                    if (rule.note.isEmpty()) destination else "$destination · ${rule.note}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = { actions.onDeleteRule(rule.id) }) {
                Icon(Icons.Filled.Delete, contentDescription = "Удалить")
            }
        }
    }
}

// MARK: - Программы

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppsSection(state: ScreenState, actions: ScreenActions) {
    var query by remember { mutableStateOf("") }

    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        Text(
            "Маршрутизация по программам",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(vertical = 12.dp),
        )
        Text(
            "Android умеет то, чего нет на компьютере: пускать через VPN только отдельные программы.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        AppsMode.entries.forEach { mode ->
            ChoiceRow(
                selected = state.config.appsMode == mode,
                title = mode.title,
                subtitle = null,
                onClick = { actions.onAppsModeChange(mode) },
            )
        }

        if (state.config.appsMode != AppsMode.OFF) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                singleLine = true,
                placeholder = { Text("Поиск программы") },
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            )

            val visible = remember(query, state.apps) {
                if (query.isBlank()) state.apps
                else state.apps.filter { it.label.contains(query, ignoreCase = true) }
            }

            LazyColumn {
                items(visible, key = { it.packageName }) { app ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                actions.onToggleApp(app.packageName, app.packageName !in state.config.selectedApps)
                            }
                            .padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(
                            checked = app.packageName in state.config.selectedApps,
                            onCheckedChange = { actions.onToggleApp(app.packageName, it) },
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(app.label, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                app.packageName,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Профиль

@Composable
private fun ProfileSection(state: ScreenState, actions: ScreenActions) {
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Профиль подключения", style = MaterialTheme.typography.titleMedium)

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (state.hasProfile) {
                    Text("Профиль загружен", fontWeight = FontWeight.SemiBold)
                    Text(
                        state.profileSummary,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                    )
                } else {
                    Text("Профиль не загружен", fontWeight = FontWeight.SemiBold)
                    Text(
                        "Возьмите файл .conf, который выдал ваш сервер WireGuard в Казахстане.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        Button(onClick = actions.onPickProfile, modifier = Modifier.fillMaxWidth()) {
            Text("Выбрать файл .conf")
        }

        if (state.hasProfile) {
            OutlinedButton(onClick = actions.onClearProfile, modifier = Modifier.fillMaxWidth()) {
                Text("Удалить профиль")
            }
        }

        Text(
            "Ключи хранятся в памяти приложения и не видны другим программам.",
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
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Настройки", style = MaterialTheme.typography.titleMedium)

        SwitchRow(
            title = "DNS-серверы из профиля",
            subtitle = "В режиме «только правила» системный DNS не трогается.",
            checked = options.useTunnelDns,
            onChange = { actions.onOptionsChange(options.copy(useTunnelDns = it)) },
        )

        SwitchRow(
            title = "Заворачивать IPv6 в туннель",
            subtitle = "Иначе сайты могут увидеть настоящий адрес по IPv6.",
            checked = options.blockIpv6,
            onChange = { actions.onOptionsChange(options.copy(blockIpv6 = it)) },
        )

        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("Пересчитывать адреса доменов")
                Text(
                    "каждые ${options.reresolveMinutes} мин",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            OutlinedButton(onClick = {
                actions.onOptionsChange(options.copy(reresolveMinutes = (options.reresolveMinutes - 1).coerceAtLeast(1)))
            }) { Text("−") }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = {
                actions.onOptionsChange(options.copy(reresolveMinutes = (options.reresolveMinutes + 1).coerceAtMost(60)))
            }) { Text("+") }
        }

        Text(
            "QP VPN · WireGuard · маршруты по адресам и по программам",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// MARK: - Мелкие кирпичики

@Composable
private fun InfoRow(title: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium, fontFamily = FontFamily.Monospace)
    }
}

@Composable
private fun ChoiceRow(selected: Boolean, title: String, subtitle: String?, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onClick)
        Column(modifier = Modifier.weight(1f).padding(start = 4.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SwitchRow(title: String, subtitle: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun WarningCard(text: String) {
    Card(
        modifier = Modifier.fillMaxWidth().widthIn(max = 560.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.3f)),
    ) {
        Text(
            text,
            modifier = Modifier.padding(14.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onErrorContainer,
        )
    }
}
