package ru.carpanel.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Цвета приборной панели: тёмный фон и голубой акцент, как в машине ночью. */
object Panel {
    val Background = Color(0xFF07101A)
    val Surface = Color(0xFF14202B)
    val SurfaceHigh = Color(0xFF1D2C39)
    val Accent = Color(0xFF4FC3F7)
    val AccentDeep = Color(0xFF0E5C7D)
    val Text = Color(0xFFE8F1F8)
    val Muted = Color(0xFF8FA6B6)
    val Danger = Color(0xFFE2695C)
    val Good = Color(0xFF4CD08A)
    val Outline = Color(0xFF2B3B49)
}

private val Scheme = darkColorScheme(
    primary = Panel.Accent,
    onPrimary = Color(0xFF042635),
    primaryContainer = Panel.AccentDeep,
    onPrimaryContainer = Panel.Text,
    secondary = Panel.Muted,
    background = Panel.Background,
    onBackground = Panel.Text,
    surface = Panel.Surface,
    onSurface = Panel.Text,
    surfaceVariant = Panel.SurfaceHigh,
    onSurfaceVariant = Panel.Muted,
    outline = Panel.Outline,
    error = Panel.Danger,
)

/** Крупнее обычного: за рулём в мелкое не всматриваются. */
private val PanelTypography = Typography(
    displayLarge = TextStyle(fontSize = 96.sp, fontWeight = FontWeight.Bold, letterSpacing = (-2).sp),
    displayMedium = TextStyle(fontSize = 64.sp, fontWeight = FontWeight.Bold, letterSpacing = (-1.5).sp),
    headlineMedium = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold),
    headlineSmall = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 17.sp),
    bodyMedium = TextStyle(fontSize = 15.sp),
    labelLarge = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium),
    labelMedium = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.2.sp),
)

@Composable
fun PanelTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Scheme, typography = PanelTypography, content = content)
}
