package ru.carpanel.ui

import android.widget.FrameLayout
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.graphics.drawable.toBitmap
import androidx.compose.foundation.Image
import ru.carpanel.apps.AppCatalog
import ru.carpanel.drive.SpeedSnapshot
import ru.carpanel.drive.TripMath
import ru.carpanel.media.MediaHub
import ru.carpanel.media.MediaSnapshot
import ru.carpanel.model.Tile
import ru.carpanel.widgets.WidgetHostController
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val ru = Locale.forLanguageTag("ru")

/** Общая подложка плитки: скруглённый прямоугольник с тонкой рамкой. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TileFrame(
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    content: @Composable androidx.compose.foundation.layout.BoxScope.() -> Unit,
) {
    val shape = RoundedCornerShape(22.dp)
    Box(
        modifier = modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outline, shape)
            .then(
                if (enabled && (onClick != null || onLongClick != null)) {
                    Modifier.combinedClickable(
                        onClick = { onClick?.invoke() },
                        onLongClick = { onLongClick?.invoke() },
                    )
                } else {
                    Modifier
                }
            ),
        content = content,
    )
}

/** Ярлык программы: значок и подпись. */
@Composable
fun AppTile(
    tile: Tile,
    catalog: AppCatalog,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val installed = remember(tile.packageName) { catalog.isInstalled(tile.packageName) }
    val label = remember(tile.packageName, tile.label) { catalog.label(tile) }
    val icon = remember(tile.packageName, installed) {
        catalog.icon(tile.packageName)
            ?.let { drawable -> runCatching { drawable.toBitmap(168, 168) }.getOrNull() }
            ?.asImageBitmap()
    }

    TileFrame(modifier = modifier, enabled = enabled, onClick = onClick, onLongClick = onLongClick) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(12.dp)
                .alpha(if (installed) 1f else 0.45f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            if (icon != null) {
                Image(
                    painter = BitmapPainter(icon),
                    contentDescription = label,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(64.dp).clip(RoundedCornerShape(16.dp)),
                )
            } else {
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = label.take(1).uppercase(ru),
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.height(10.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
            if (!installed) {
                Text(
                    text = "не установлена",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** Спидометр: крупные цифры и состояние приёмника. */
@Composable
fun SpeedTile(
    snapshot: SpeedSnapshot,
    nowMs: Long,
    miles: Boolean,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onRequestPermission: () -> Unit,
    onLongClick: () -> Unit,
) {
    TileFrame(modifier = modifier, enabled = enabled, onLongClick = onLongClick) {
        Column(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            when {
                !snapshot.allowed -> {
                    Text("Спидометр", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Нужен доступ к местоположению",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                    TextButton(onClick = onRequestPermission, enabled = enabled) { Text("Разрешить") }
                }

                else -> {
                    val fresh = snapshot.isFresh(nowMs)
                    Text(
                        text = if (fresh) Format.speed(snapshot.speedMs, miles) else "—",
                        style = MaterialTheme.typography.displayLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                    )
                    Text(
                        text = Format.speedUnit(miles),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (!fresh) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = if (snapshot.gpsEnabled) "ищу спутники" else "GPS выключен",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

/** Поездка: путь, средняя и наибольшая скорость, время в движении. */
@Composable
fun TripTile(
    snapshot: SpeedSnapshot,
    miles: Boolean,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onReset: () -> Unit,
    onLongClick: () -> Unit,
) {
    TileFrame(modifier = modifier, enabled = enabled, onLongClick = onLongClick) {
        Column(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.Center,
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Поездка", style = MaterialTheme.typography.titleMedium)
                IconButton(onClick = onReset, enabled = enabled) {
                    Icon(Icons.Filled.Refresh, contentDescription = "Обнулить")
                }
            }
            Spacer(Modifier.height(4.dp))
            TripLine("Путь", Format.distance(snapshot.trip.distanceM, miles))
            TripLine("Средняя", Format.speed(TripMath.averageMs(snapshot.trip), miles) + " " + Format.speedUnit(miles))
            TripLine("Максимум", Format.speed(snapshot.trip.maxSpeedMs, miles) + " " + Format.speedUnit(miles))
            TripLine("В движении", Format.duration(snapshot.trip.movingMs))
        }
    }
}

@Composable
private fun TripLine(title: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
    }
}

/** Часы и дата. */
@Composable
fun ClockTile(
    nowMs: Long,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onLongClick: () -> Unit,
) {
    val time = remember(nowMs / 60_000L) { SimpleDateFormat("HH:mm", ru).format(Date(nowMs)) }
    val date = remember(nowMs / 3_600_000L) { SimpleDateFormat("EEEE, d MMMM", ru).format(Date(nowMs)) }

    TileFrame(modifier = modifier, enabled = enabled, onLongClick = onLongClick) {
        Column(
            modifier = Modifier.fillMaxSize().padding(14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(time, style = MaterialTheme.typography.displayMedium, maxLines = 1)
            Text(
                text = date.replaceFirstChar { it.uppercase(ru) },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/** Что играет: название трека и три кнопки. */
@Composable
fun MediaTile(
    snapshot: MediaSnapshot,
    hub: MediaHub,
    preferred: String?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onGrantAccess: () -> Unit,
    onLongClick: () -> Unit,
) {
    TileFrame(modifier = modifier, enabled = enabled, onLongClick = onLongClick) {
        Column(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.Center,
        ) {
            if (!snapshot.available) {
                Text("Музыка", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Нужен доступ к уведомлениям — иначе система не отдаёт управление проигрывателем",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(onClick = onGrantAccess, enabled = enabled) { Text("Открыть настройки") }
                return@Column
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.MusicNote,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.size(8.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = snapshot.title.ifBlank { "Ничего не играет" },
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (snapshot.subtitle.isNotBlank()) {
                        Text(
                            text = snapshot.subtitle,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
            Spacer(Modifier.height(6.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = { hub.previous(preferred) }, enabled = enabled) {
                    Icon(Icons.Filled.SkipPrevious, contentDescription = "Назад", modifier = Modifier.size(34.dp))
                }
                IconButton(onClick = { hub.playPause(preferred) }, enabled = enabled) {
                    Icon(
                        imageVector = if (snapshot.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = if (snapshot.playing) "Пауза" else "Играть",
                        modifier = Modifier.size(40.dp),
                    )
                }
                IconButton(onClick = { hub.next(preferred) }, enabled = enabled) {
                    Icon(Icons.Filled.SkipNext, contentDescription = "Дальше", modifier = Modifier.size(34.dp))
                }
            }
        }
    }
}

/** Настоящий системный виджет чужой программы. */
@Composable
fun WidgetTile(
    tile: Tile,
    widgets: WidgetHostController,
    modifier: Modifier = Modifier,
    editing: Boolean = false,
    onLongClick: () -> Unit,
) {
    val info = remember(tile.widgetId) { widgets.info(tile.widgetId) }

    if (info != null && editing) {
        // Пока плитки двигают, живой виджет заменяем карточкой: иначе он
        // перехватывает касания и утащить его не получится.
        TileFrame(modifier = modifier, enabled = false) {
            Column(
                modifier = Modifier.fillMaxSize().padding(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text("Виджет", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    text = widgets.label(info),
                    style = MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        return
    }

    if (info == null) {
        TileFrame(modifier = modifier, onLongClick = onLongClick) {
            Column(
                modifier = Modifier.fillMaxSize().padding(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text("Виджет недоступен", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                Text(
                    "Программу удалили или система забыла привязку",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
        return
    }

    TileFrame(modifier = modifier, enabled = !editing, onLongClick = onLongClick) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val widthDp = maxWidth.value.toInt()
            val heightDp = maxHeight.value.toInt()
            AndroidView(
                modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(22.dp)),
                factory = { viewContext ->
                    widgets.createView(tile.widgetId) ?: FrameLayout(viewContext)
                },
                update = { view ->
                    val host = view as? android.appwidget.AppWidgetHostView ?: return@AndroidView
                    widgets.resize(host, tile.widgetId, widthDp, heightDp)
                },
            )
        }
    }
}
