package ru.carpanel.ui

import android.appwidget.AppWidgetProviderInfo
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import ru.carpanel.apps.AppCatalog
import ru.carpanel.apps.AppEntry
import ru.carpanel.drive.SpeedSnapshot
import ru.carpanel.media.MediaHub
import ru.carpanel.media.MediaSnapshot
import ru.carpanel.model.PanelConfig
import ru.carpanel.model.Tile
import ru.carpanel.model.TileKind
import ru.carpanel.widgets.WidgetHostController

/** Всё, что панель просит сделать снаружи: запустить, добавить, сохранить. */
class PanelActions(
    val onMove: (Long, Int, Int) -> Unit,
    val onResize: (Long, Int, Int) -> Unit,
    val onRemove: (Long) -> Unit,
    val onLaunch: (Tile) -> Unit,
    val onAddApp: (AppEntry) -> Unit,
    val onAddBuiltin: (TileKind) -> Unit,
    val onPickWidget: (AppWidgetProviderInfo) -> Unit,
    val onResetTrip: () -> Unit,
    val onRequestLocation: () -> Unit,
    val onNotificationAccess: () -> Unit,
    val onColumns: (Int) -> Unit,
    val onRows: (Int) -> Unit,
    val onKeepScreenOn: (Boolean) -> Unit,
    val onMiles: (Boolean) -> Unit,
    val onRussifyLabels: (Boolean) -> Unit,
    val onForceRussian: (Boolean) -> Unit,
    val onRename: (Long, String) -> Unit,
    val onHomeScreen: (Boolean) -> Unit,
    val onResetBoard: () -> Unit,
)

private enum class Overlay { NONE, ADD, SETTINGS }

@Composable
fun PanelScreen(
    config: PanelConfig,
    speed: SpeedSnapshot,
    catalog: AppCatalog,
    media: MediaHub,
    widgets: WidgetHostController,
    actions: PanelActions,
) {
    var editing by remember { mutableStateOf(false) }
    var overlay by remember { mutableStateOf(Overlay.NONE) }
    var renaming by remember { mutableStateOf<Tile?>(null) }

    // Одни часы на всю панель: по ним живут часы, спидометр и проигрыватель.
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1_000L)
        }
    }

    val hasMediaTile = config.board.tiles.any { it.kind == TileKind.MEDIA }
    val mediaPreferred = config.board.tiles.firstOrNull { it.kind == TileKind.MEDIA }?.packageName
    var mediaSnapshot by remember { mutableStateOf(MediaSnapshot()) }
    LaunchedEffect(hasMediaTile, mediaPreferred) {
        while (hasMediaTile) {
            mediaSnapshot = media.snapshot(mediaPreferred)
            delay(1_500L)
        }
    }

    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize()) {
        when (overlay) {
            Overlay.ADD -> AddTileScreen(
                catalog = catalog,
                widgets = widgets,
                russify = config.settings.russifyLabels,
                onAddApp = { entry ->
                    actions.onAddApp(entry)
                    overlay = Overlay.NONE
                },
                onAddBuiltin = { kind ->
                    actions.onAddBuiltin(kind)
                    overlay = Overlay.NONE
                },
                onAddWidget = { info ->
                    actions.onPickWidget(info)
                    overlay = Overlay.NONE
                },
                onClose = { overlay = Overlay.NONE },
            )

            Overlay.SETTINGS -> SettingsScreen(
                config = config,
                speed = speed,
                mediaAccess = media.hasAccess(),
                actions = actions,
                onClose = { overlay = Overlay.NONE },
            )

            Overlay.NONE -> Column(modifier = Modifier.fillMaxSize().padding(14.dp)) {
                PanelBar(
                    editing = editing,
                    onAdd = { overlay = Overlay.ADD },
                    onEdit = { editing = !editing },
                    onSettings = { overlay = Overlay.SETTINGS },
                )
                Spacer(Modifier.size(12.dp))
                if (config.board.tiles.isEmpty()) {
                    EmptyHint()
                    return@Column
                }
                BoardGrid(
                    board = config.board,
                    editing = editing,
                    modifier = Modifier.fillMaxSize(),
                    onMove = actions.onMove,
                    onResize = actions.onResize,
                    onRemove = actions.onRemove,
                    onRename = { tile -> renaming = tile },
                ) { tile ->
                    TileContent(
                        tile = tile,
                        editing = editing,
                        config = config,
                        speed = speed,
                        mediaSnapshot = mediaSnapshot,
                        nowMs = now,
                        catalog = catalog,
                        media = media,
                        widgets = widgets,
                        actions = actions,
                        onEnterEdit = { editing = true },
                    )
                }
            }
        }

        renaming?.let { tile ->
            RenameDialog(
                initial = catalog.label(tile, config.settings.russifyLabels),
                onDismiss = { renaming = null },
                onConfirm = { name ->
                    actions.onRename(tile.id, name)
                    renaming = null
                },
            )
        }
    }
}

/** Своя подпись плитки — самый прямой способ перевести чужое название. */
@Composable
private fun RenameDialog(
    initial: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var text by remember { mutableStateOf(initial) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Название плитки") },
        text = {
            Column {
                Text(
                    "Подпись можно заменить русской — например, вместо 设置 написать «Настройки».",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.size(12.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    singleLine = true,
                    label = { Text("Подпись") },
                )
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(text) }) { Text("Сохранить") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

@Composable
private fun PanelBar(
    editing: Boolean,
    onAdd: () -> Unit,
    onEdit: () -> Unit,
    onSettings: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column {
            Text("Панель L9", style = MaterialTheme.typography.titleLarge)
            Text(
                text = if (editing) "Тяните плитки, меняйте размер кнопками Ш и В" else "Долгое нажатие на плитку — правка",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.weight(1f))
        FilledTonalButton(onClick = onAdd) {
            Icon(Icons.Filled.Add, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text("Плитка")
        }
        Spacer(Modifier.width(10.dp))
        FilledTonalButton(onClick = onEdit) {
            Icon(
                imageVector = if (editing) Icons.Filled.Done else Icons.Filled.Edit,
                contentDescription = null,
            )
            Spacer(Modifier.width(8.dp))
            Text(if (editing) "Готово" else "Править")
        }
        Spacer(Modifier.width(10.dp))
        FilledTonalButton(onClick = onSettings) {
            Icon(Icons.Filled.Settings, contentDescription = "Настройки")
        }
    }
}

/** Что рисовать внутри клетки — решает тип плитки. */
@Composable
private fun TileContent(
    tile: Tile,
    editing: Boolean,
    config: PanelConfig,
    speed: SpeedSnapshot,
    mediaSnapshot: MediaSnapshot,
    nowMs: Long,
    catalog: AppCatalog,
    media: MediaHub,
    widgets: WidgetHostController,
    actions: PanelActions,
    onEnterEdit: () -> Unit,
) {
    val modifier = Modifier.fillMaxSize()
    val miles = config.settings.miles

    when (tile.kind) {
        TileKind.APP -> AppTile(
            tile = tile,
            catalog = catalog,
            russify = config.settings.russifyLabels,
            modifier = modifier,
            enabled = !editing,
            onClick = { actions.onLaunch(tile) },
            onLongClick = onEnterEdit,
        )

        TileKind.SPEED -> SpeedTile(
            snapshot = speed,
            nowMs = nowMs,
            miles = miles,
            modifier = modifier,
            enabled = !editing,
            onRequestPermission = actions.onRequestLocation,
            onLongClick = onEnterEdit,
        )

        TileKind.TRIP -> TripTile(
            snapshot = speed,
            miles = miles,
            modifier = modifier,
            enabled = !editing,
            onReset = actions.onResetTrip,
            onLongClick = onEnterEdit,
        )

        TileKind.CLOCK -> ClockTile(
            nowMs = nowMs,
            modifier = modifier,
            enabled = !editing,
            onLongClick = onEnterEdit,
        )

        TileKind.MEDIA -> MediaTile(
            snapshot = mediaSnapshot,
            hub = media,
            preferred = tile.packageName,
            modifier = modifier,
            enabled = !editing,
            onGrantAccess = actions.onNotificationAccess,
            onLongClick = onEnterEdit,
        )

        TileKind.WIDGET -> WidgetTile(
            tile = tile,
            widgets = widgets,
            editing = editing,
            modifier = modifier,
            onLongClick = onEnterEdit,
        )
    }
}

/** Пустая панель — подсказка, что делать дальше. */
@Composable
fun EmptyHint(modifier: Modifier = Modifier) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text("Панель пуста", style = MaterialTheme.typography.headlineSmall)
            Text(
                "Нажмите «Плитка» и добавьте навигатор, музыку или спидометр",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
