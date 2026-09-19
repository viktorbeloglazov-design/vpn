package kz.qpvpn.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val BrandLight = lightColorScheme(
    primary = Color(0xFF0B6E93),
    onPrimary = Color.White,
    secondary = Color(0xFF3AAED2),
    background = Color(0xFFF3F5F8),
    surface = Color(0xFFFFFFFF),
)

private val BrandDark = darkColorScheme(
    primary = Color(0xFF4FC0E6),
    onPrimary = Color(0xFF00212F),
    secondary = Color(0xFF7FD4EC),
    background = Color(0xFF0B1116),
    surface = Color(0xFF151D25),
)

@Composable
fun QpVpnTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current

    // На Android 12 и новее берём палитру системы — на One UI это выглядит роднее.
    val colors = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> BrandDark
        else -> BrandLight
    }

    MaterialTheme(colorScheme = colors, content = content)
}
