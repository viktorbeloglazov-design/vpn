package ru.carpanel.ui

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.remember
import ru.carpanel.apps.AppCatalog
import ru.carpanel.drive.SpeedSnapshot
import ru.carpanel.model.AppSet
import ru.carpanel.model.Grid
import ru.carpanel.model.PanelConfig

/** Настройки панели: размер сетки, разрешения, домашний экран. */
@Composable
fun SettingsScreen(
    config: PanelConfig,
    speed: SpeedSnapshot,
    catalog: AppCatalog,
    mediaAccess: Boolean,
    actions: PanelActions,
    onAddSetApp: () -> Unit,
    onClose: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(18.dp)
            .verticalScroll(rememberScrollState()),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Настройки", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onClose) { Text("Закрыть") }
        }
        Spacer(Modifier.height(16.dp))

        Section("Сетка") {
            Stepper(
                title = "Столбцов",
                value = config.board.columns,
                min = Grid.MIN_COLUMNS,
                max = Grid.MAX_COLUMNS,
                onChange = actions.onColumns,
            )
            Stepper(
                title = "Рядов",
                value = config.board.rows,
                min = 1,
                max = 6,
                onChange = actions.onRows,
            )
        }

        Section("Экран") {
            Toggle(
                title = "Не гасить экран",
                hint = "Пока панель открыта, подсветка не уходит",
                checked = config.settings.keepScreenOn,
                onChange = actions.onKeepScreenOn,
            )
            Toggle(
                title = "Мили вместо километров",
                hint = "Спидометр и счётчик поездки",
                checked = config.settings.miles,
                onChange = actions.onMiles,
            )
            Toggle(
                title = "Предлагать как домашний экран",
                hint = "После включения система спросит, чем открывать кнопку «домой»",
                checked = config.settings.homeScreen,
                onChange = actions.onHomeScreen,
            )
        }

        Section("Набор программ") {
            Toggle(
                title = "Показывать набор",
                hint = "Плитка с набором на главном экране панели и содержимое виджета для домашнего экрана машины",
                checked = config.appSet.enabled,
                onChange = actions.onAppSetEnabled,
            )
            Spacer(Modifier.height(6.dp))

            if (config.appSet.packages.isEmpty()) {
                Text(
                    "Набор пуст — добавьте в него программы.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                for (packageName in config.appSet.packages) {
                    SetRow(
                        title = remember(packageName, config.settings.russifyLabels) {
                            catalog.labelOf(packageName, config.settings.russifyLabels)
                        },
                        onRemove = { actions.onRemoveFromSet(packageName) },
                    )
                }
            }

            Spacer(Modifier.height(10.dp))
            OutlinedButton(
                onClick = onAddSetApp,
                enabled = config.appSet.packages.size < AppSet.MAX,
            ) {
                Text("Добавить программу")
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "Виджет «Набор программ» кладётся на штатный рабочий стол машины так же, как её " +
                    "собственные виджеты — долгим нажатием по свободному месту. Если прошивка чужих " +
                    "виджетов не принимает, набор всё равно остаётся плиткой в панели.",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Section("Язык") {
            Toggle(
                title = "Русские названия программ",
                hint = "Китайские и английские подписи заменяются русскими по словарю",
                checked = config.settings.russifyLabels,
                onChange = actions.onRussifyLabels,
            )
            Toggle(
                title = "Интерфейс всегда по-русски",
                hint = "Даже если система машины говорит по-китайски или по-английски",
                checked = config.settings.forceRussian,
                onChange = actions.onForceRussian,
            )
            Text(
                "Подпись любой плитки меняется вручную: «Править» → кнопка «Аа» на плитке. " +
                    "Меню самой машины программа переписать не может — только то, что показывает сама.",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Section("Разрешения") {
            Permission(
                title = "Местоположение",
                granted = speed.allowed,
                hint = if (speed.allowed) "Спидометр работает" else "Без него спидометр пустой",
                action = "Запросить",
                onClick = actions.onRequestLocation,
            )
            Permission(
                title = "Доступ к уведомлениям",
                granted = mediaAccess,
                hint = if (mediaAccess) "Кнопки проигрывателя работают" else "Нужен, чтобы управлять Яндекс Музыкой",
                action = "Открыть настройки",
                onClick = actions.onNotificationAccess,
            )
        }

        Section("Раскладка") {
            Text(
                "Вернуть первоначальные плитки: спидометр, часы, музыка, навигатор.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(10.dp))
            OutlinedButton(onClick = actions.onResetBoard) { Text("Сбросить раскладку") }
        }

        Spacer(Modifier.height(20.dp))
        Text(
            "Панель L9 · виджеты и ярлыки для экрана автомобиля",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun SetRow(title: String, onRemove: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        TextButton(onClick = onRemove) { Text("Убрать") }
    }
}

@Composable
private fun Section(title: String, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 16.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(18.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(12.dp))
        content()
    }
}

@Composable
private fun Stepper(title: String, value: Int, min: Int, max: Int, onChange: (Int) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge)
        Spacer(Modifier.weight(1f))
        Round(label = "−", enabled = value > min) { onChange(value - 1) }
        Box(modifier = Modifier.size(width = 62.dp, height = 44.dp), contentAlignment = Alignment.Center) {
            Text("$value", style = MaterialTheme.typography.headlineSmall)
        }
        Round(label = "+", enabled = value < max) { onChange(value + 1) }
    }
}

@Composable
private fun Round(label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(48.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(
                if (enabled) MaterialTheme.colorScheme.surfaceVariant
                else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
            )
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = MaterialTheme.typography.headlineSmall)
    }
}

@Composable
private fun Toggle(title: String, hint: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(hint, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun Permission(title: String, granted: Boolean, hint: String, action: String, onClick: () -> Unit) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                Text(
                    hint,
                    style = MaterialTheme.typography.labelMedium,
                    color = if (granted) Panel.Good else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!granted) {
                OutlinedButton(onClick = onClick) { Text(action) }
            } else {
                Text("дано", style = MaterialTheme.typography.labelLarge, color = Panel.Good)
            }
        }
        Spacer(Modifier.height(6.dp))
        HorizontalDivider(color = MaterialTheme.colorScheme.outline)
    }
}
