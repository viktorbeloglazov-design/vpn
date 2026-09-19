package kz.carlink.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kz.carlink.LinkState
import kz.carlink.aa.Stage
import kz.carlink.projection.ProjectionMode

@Composable
fun CarLinkScreen(
    state: LinkState,
    accessory: String?,
    mode: ProjectionMode,
    hasCredentials: Boolean,
    injectorEnabled: Boolean,
    log: List<String>,
    passwordRequested: Boolean,
    onModeChange: (ProjectionMode) -> Unit,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onPickCredentials: () -> Unit,
    onForgetCredentials: () -> Unit,
    onPasswordEntered: (String) -> Unit,
    onPasswordCancelled: () -> Unit,
    onOpenAccessibility: () -> Unit,
    onCopyLog: () -> Unit,
    onClearLog: () -> Unit,
) {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Scaffold { padding ->
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(16.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    StatusCard(state, accessory)
                    if (!hasCredentials) CertificateWarning()
                    ModeCard(mode, injectorEnabled, onModeChange, onOpenAccessibility)
                    CredentialsCard(hasCredentials, onPickCredentials, onForgetCredentials)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Button(onClick = onConnect, enabled = !state.running) {
                            Text("Подключиться")
                        }
                        OutlinedButton(onClick = onDisconnect, enabled = state.running) {
                            Text("Отключиться")
                        }
                    }
                    LogCard(log, onCopyLog, onClearLog)
                }
            }
        }
    }

    if (passwordRequested) {
        PasswordDialog(onPasswordEntered, onPasswordCancelled)
    }
}

@Composable
private fun StatusCard(state: LinkState, accessory: String?) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(state.stage.title, style = MaterialTheme.typography.headlineSmall)
            if (state.detail.isNotBlank()) {
                Text(state.detail, style = MaterialTheme.typography.bodyMedium)
            }
            Text(
                accessory?.let { "Провод: $it" } ?: "Провод: машина не найдена",
                style = MaterialTheme.typography.bodySmall,
            )
            if (state.stage == Stage.STREAMING) {
                Text("Экран отдан машине", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun CertificateWarning() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Нет ключа, который примет машина", style = MaterialTheme.typography.titleMedium)
            Text(
                "Серийное головное устройство проверяет, что сертификат телефона подписан Google. " +
                    "С отладочным ключом соединение дойдёт до рукопожатия и оборвётся — " +
                    "это видно в журнале. Порядок действий описан в README проекта.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun ModeCard(
    mode: ProjectionMode,
    injectorEnabled: Boolean,
    onModeChange: (ProjectionMode) -> Unit,
    onOpenAccessibility: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Что показывать машине", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = mode == ProjectionMode.CAR_UI,
                    onClick = { onModeChange(ProjectionMode.CAR_UI) },
                    label = { Text("Свой экран") },
                )
                FilterChip(
                    selected = mode == ProjectionMode.MIRROR,
                    onClick = { onModeChange(ProjectionMode.MIRROR) },
                    label = { Text("Зеркало телефона") },
                )
            }
            Text(
                when (mode) {
                    ProjectionMode.CAR_UI ->
                        "Часы и крупные кнопки музыки. Разрешение на показ экрана не нужно, " +
                            "подключение начинается само."
                    ProjectionMode.MIRROR ->
                        "Экран телефона целиком: карты, мессенджеры, всё подряд. " +
                            "Нужно разрешение на показ экрана, а нажатия идут через службу " +
                            "специальных возможностей."
                },
                style = MaterialTheme.typography.bodySmall,
            )
            if (mode == ProjectionMode.MIRROR && !injectorEnabled) {
                OutlinedButton(onClick = onOpenAccessibility) {
                    Text("Включить нажатия с экрана машины")
                }
            }
        }
    }
}

@Composable
private fun CredentialsCard(
    hasCredentials: Boolean,
    onPick: () -> Unit,
    onForget: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Ключ для рукопожатия", style = MaterialTheme.typography.titleMedium)
            Text(
                if (hasCredentials) "Загружен файл PKCS#12." else "Отладочный самоподписанный ключ.",
                style = MaterialTheme.typography.bodySmall,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onPick) { Text("Выбрать .p12") }
                if (hasCredentials) TextButton(onClick = onForget) { Text("Удалить") }
            }
        }
    }
}

@Composable
private fun LogCard(log: List<String>, onCopy: () -> Unit, onClear: () -> Unit) {
    val listState = rememberLazyListState()
    LaunchedEffect(log.size) {
        if (log.isNotEmpty()) listState.animateScrollToItem(log.size - 1)
    }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Журнал", style = MaterialTheme.typography.titleMedium)
                Row {
                    TextButton(onClick = onCopy) { Text("Копировать") }
                    TextButton(onClick = onClear) { Text("Очистить") }
                }
            }
            SelectionContainer {
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(320.dp)
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                ) {
                    items(log) { line ->
                        Text(
                            line,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 1.dp),
                        )
                    }
                }
            }
            if (log.isEmpty()) {
                Spacer(modifier = Modifier.height(0.dp))
                Text("Пока пусто. Воткните провод в порт USB машины.", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun PasswordDialog(onEntered: (String) -> Unit, onCancelled: () -> Unit) {
    var password by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onCancelled,
        title = { Text("Пароль файла ключа") },
        text = {
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                label = { Text("Пароль PKCS#12") },
            )
        },
        confirmButton = { TextButton(onClick = { onEntered(password) }) { Text("Готово") } },
        dismissButton = { TextButton(onClick = onCancelled) { Text("Отмена") } },
    )
}
