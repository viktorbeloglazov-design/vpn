package kz.qpvpn.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Фирменные цвета: небо Казахстана из иконки и спокойные графитовые подложки. */
object Brand {
    val Sky = Color(0xFF3ABEE8)
    val Ocean = Color(0xFF0E7FA8)
    val Deep = Color(0xFF084A6A)
    val Connected = Color(0xFF2FBF87)
    val Waiting = Color(0xFFE2A33C)
    val Danger = Color(0xFFE2695C)
}

/** Дополнительные цвета, которых нет в схеме Material. */
data class AppColors(
    val heroGradient: Brush,
    val connected: Color,
    val waiting: Color,
    val danger: Color,
    val onHero: Color,
    val heroMuted: Color,
    val cardBorder: Color,
)

val LocalAppColors = staticCompositionLocalOf {
    AppColors(
        heroGradient = Brush.verticalGradient(listOf(Brand.Ocean, Brand.Deep)),
        connected = Brand.Connected,
        waiting = Brand.Waiting,
        danger = Brand.Danger,
        onHero = Color.White,
        heroMuted = Color.White.copy(alpha = 0.72f),
        cardBorder = Color.Black.copy(alpha = 0.06f),
    )
}

private val LightScheme = lightColorScheme(
    primary = Brand.Ocean,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD5EEF8),
    onPrimaryContainer = Color(0xFF05384F),
    secondary = Color(0xFF4C6472),
    background = Color(0xFFF3F6F9),
    onBackground = Color(0xFF111A20),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF111A20),
    surfaceVariant = Color(0xFFE9EFF4),
    onSurfaceVariant = Color(0xFF4A5B66),
    outline = Color(0xFFBFCCD6),
    error = Brand.Danger,
)

private val DarkScheme = darkColorScheme(
    primary = Brand.Sky,
    onPrimary = Color(0xFF00212E),
    primaryContainer = Color(0xFF0C3B50),
    onPrimaryContainer = Color(0xFFCCEBF7),
    secondary = Color(0xFF9CB4C2),
    background = Color(0xFF0A1015),
    onBackground = Color(0xFFE6EDF3),
    surface = Color(0xFF141C24),
    onSurface = Color(0xFFE6EDF3),
    surfaceVariant = Color(0xFF1E2932),
    onSurfaceVariant = Color(0xFF9FB2BF),
    outline = Color(0xFF32424E),
    error = Brand.Danger,
)

private val AppTypography = Typography(
    headlineMedium = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    headlineSmall = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.3).sp),
    titleLarge = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 15.sp),
    bodyMedium = TextStyle(fontSize = 14.sp),
    bodySmall = TextStyle(fontSize = 12.5.sp),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.2.sp),
)

@Composable
fun QpVpnTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme = if (dark) DarkScheme else LightScheme

    val appColors = AppColors(
        heroGradient = if (dark) {
            Brush.verticalGradient(listOf(Color(0xFF10506E), Color(0xFF0A2534)))
        } else {
            Brush.verticalGradient(listOf(Brand.Ocean, Brand.Deep))
        },
        connected = Brand.Connected,
        waiting = Brand.Waiting,
        danger = Brand.Danger,
        onHero = Color.White,
        heroMuted = Color.White.copy(alpha = 0.72f),
        cardBorder = if (dark) Color.White.copy(alpha = 0.06f) else Color.Black.copy(alpha = 0.05f),
    )

    CompositionLocalProvider(LocalAppColors provides appColors) {
        MaterialTheme(colorScheme = scheme, typography = AppTypography, content = content)
    }
}
