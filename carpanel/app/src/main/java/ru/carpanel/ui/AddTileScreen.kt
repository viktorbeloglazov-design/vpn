package ru.carpanel.ui

import android.appwidget.AppWidgetProviderInfo
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Image
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import ru.carpanel.apps.AppCatalog
import ru.carpanel.apps.AppEntry
import ru.carpanel.model.TileKind
import ru.carpanel.widgets.WidgetHostController

private enum class AddTab(val title: String) {
    BUILTIN("Приборы"),
    APPS("Программы"),
    WIDGETS("Виджеты"),
}

private data class Builtin(val kind: TileKind, val title: String, val hint: String)

private val builtins = listOf(
    Builtin(TileKind.SPEED, "Спидометр", "Скорость по GPS крупными цифрами"),
    Builtin(TileKind.TRIP, "Поездка", "Путь, средняя и наибольшая скорость"),
    Builtin(TileKind.CLOCK, "Часы", "Время и дата"),
    Builtin(TileKind.MEDIA, "Музыка", "Трек и кнопки любого проигрывателя"),
)

/** Выбор новой плитки: прибор, программа или чужой виджет. */
@Composable
fun AddTileScreen(
    catalog: AppCatalog,
    widgets: WidgetHostController,
    russify: Boolean = true,
    /** Режим набора программ: только список программ, без приборов и виджетов. */
    onlyApps: Boolean = false,
    onAddApp: (AppEntry) -> Unit,
    onAddBuiltin: (TileKind) -> Unit,
    onAddWidget: (AppWidgetProviderInfo) -> Unit,
    onClose: () -> Unit,
) {
    var tab by remember { mutableStateOf(if (onlyApps) AddTab.APPS else AddTab.BUILTIN) }

    val apps by produceState(initialValue = emptyList<Pair<AppEntry, Boolean>>(), russify) {
        value = withContext(Dispatchers.IO) {
            catalog.installed(russify).map { it to true } + catalog.suggestions().map { it to false }
        }
    }
    val providers by produceState(initialValue = emptyList<AppWidgetProviderInfo>()) {
        value = withContext(Dispatchers.IO) { widgets.providers() }
    }

    Column(modifier = Modifier.fillMaxSize().padding(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(
                text = if (onlyApps) "Программа в набор" else "Добавить плитку",
                style = MaterialTheme.typography.headlineSmall,
            )
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onClose) { Text("Закрыть") }
        }
        Spacer(Modifier.height(12.dp))

        if (!onlyApps) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (item in AddTab.entries) {
                    Tab(title = item.title, selected = tab == item) { tab = item }
                }
            }
            Spacer(Modifier.height(14.dp))
        }

        when (tab) {
            AddTab.BUILTIN -> LazyVerticalGrid(
                columns = GridCells.Adaptive(240.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(builtins) { item ->
                    Card(onClick = { onAddBuiltin(item.kind) }) {
                        Text(item.title, style = MaterialTheme.typography.titleMedium)
                        Text(
                            item.hint,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            AddTab.APPS -> LazyVerticalGrid(
                columns = GridCells.Adaptive(180.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(apps) { (entry, installed) ->
                    Card(onClick = { onAddApp(entry) }) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            AppIcon(catalog, entry.packageName)
                            Spacer(Modifier.width(10.dp))
                            Column {
                                Text(
                                    entry.label,
                                    style = MaterialTheme.typography.titleMedium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                if (!installed) {
                                    Text(
                                        "ещё не установлена",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            AddTab.WIDGETS -> if (providers.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        "Установленные программы не предлагают виджетов",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(240.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(providers) { info ->
                        Card(onClick = { onAddWidget(info) }) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                AppIcon(catalog, info.provider.packageName)
                                Spacer(Modifier.width(10.dp))
                                Column {
                                    Text(
                                        widgets.label(info),
                                        style = MaterialTheme.typography.titleMedium,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Text(
                                        catalog.labelOf(info.provider.packageName, russify),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AppIcon(catalog: AppCatalog, packageName: String) {
    val icon = remember(packageName) {
        catalog.icon(packageName)
            ?.let { drawable -> runCatching { drawable.toBitmap(120, 120) }.getOrNull() }
            ?.asImageBitmap()
    }
    if (icon != null) {
        Image(
            painter = BitmapPainter(icon),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)),
        )
    } else {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
        )
    }
}

@Composable
private fun Tab(title: String, selected: Boolean, onClick: () -> Unit) {
    val background = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(14.dp))
            .background(background)
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 12.dp),
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun Card(onClick: () -> Unit, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClick = onClick)
            .padding(16.dp),
        content = content,
    )
}
