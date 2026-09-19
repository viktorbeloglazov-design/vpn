package kz.qpvpn.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Power
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kz.qpvpn.model.ConnectionState

/** Крупная кнопка включения с дышащим кольцом, пока идёт подключение. */
@Composable
fun PowerButton(
    state: ConnectionState,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAppColors.current

    val target = when (state) {
        ConnectionState.CONNECTED -> colors.connected
        ConnectionState.CONNECTING -> colors.waiting
        ConnectionState.ERROR -> colors.danger
        ConnectionState.DISCONNECTED -> Color.White.copy(alpha = 0.55f)
    }
    val tint by animateColorAsState(targetValue = target, animationSpec = tween(400), label = "powerTint")

    val transition = rememberInfiniteTransition(label = "powerPulse")
    val pulse by transition.animateFloat(
        initialValue = 1f,
        targetValue = if (state == ConnectionState.CONNECTING) 1.14f else 1.04f,
        animationSpec = infiniteRepeatable(
            animation = tween(if (state == ConnectionState.CONNECTING) 900 else 2600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulseScale",
    )

    val active = state != ConnectionState.DISCONNECTED

    Box(modifier = modifier.size(190.dp), contentAlignment = Alignment.Center) {
        if (active) {
            Box(
                modifier = Modifier
                    .size(170.dp)
                    .scale(pulse)
                    .clip(CircleShape)
                    .background(tint.copy(alpha = 0.16f))
            )
        }
        Box(
            modifier = Modifier
                .size(136.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = if (active) 0.20f else 0.12f))
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(104.dp)
                    .clip(CircleShape)
                    .background(tint.copy(alpha = 0.22f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Power,
                    contentDescription = if (active) "Выключить" else "Включить",
                    tint = if (state == ConnectionState.DISCONNECTED) Color.White else tint,
                    modifier = Modifier.size(52.dp),
                )
            }
        }
    }
}

/** Показатель в шапке: подпись сверху, значение крупнее снизу. */
@Composable
fun HeroStat(label: String, value: String, modifier: Modifier = Modifier) {
    val colors = LocalAppColors.current
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = colors.heroMuted,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            value,
            style = MaterialTheme.typography.titleMedium,
            color = colors.onHero,
            fontFamily = FontFamily.Monospace,
        )
    }
}

@Composable
fun SectionHeader(title: String, subtitle: String? = null, modifier: Modifier = Modifier) {
    Column(modifier = modifier.padding(top = 20.dp, bottom = 10.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge)
        if (subtitle != null) {
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun InfoCard(content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, LocalAppColors.current.cardBorder),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            content()
        }
    }
}

@Composable
fun KeyValueRow(label: String, value: String, monospace: Boolean = false) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = if (monospace) FontFamily.Monospace else FontFamily.Default,
            fontWeight = FontWeight.Medium,
        )
    }
}

fun plural(count: Int, one: String, few: String, many: String): String {
    val mod100 = count % 100
    if (mod100 in 11..14) return many
    return when (count % 10) {
        1 -> one
        2, 3, 4 -> few
        else -> many
    }
}
