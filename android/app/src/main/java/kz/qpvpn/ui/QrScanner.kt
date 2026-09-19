package kz.qpvpn.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import java.util.EnumMap
import java.util.concurrent.Executors

/**
 * Камера с чтением QR-кода.
 *
 * Разбор кадров идёт библиотекой ZXing, а не сервисами Google: на телефонах
 * для китайского рынка — а Samsung W-серии именно такой — сервисов Google
 * может не быть вовсе.
 */
@Composable
fun QrScannerScreen(
    onResult: (String) -> Unit,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var granted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    var handled by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted = it }

    LaunchedEffect(Unit) {
        if (!granted) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    val executor = remember { Executors.newSingleThreadExecutor() }
    DisposableEffect(Unit) {
        onDispose { executor.shutdown() }
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        if (granted) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { viewContext ->
                    val previewView = PreviewView(viewContext)
                    val providerFuture = ProcessCameraProvider.getInstance(viewContext)

                    providerFuture.addListener({
                        val provider = providerFuture.get()

                        val preview = Preview.Builder().build().also {
                            it.setSurfaceProvider(previewView.surfaceProvider)
                        }

                        val analysis = ImageAnalysis.Builder()
                            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                            .build()

                        analysis.setAnalyzer(executor) { image ->
                            if (!handled) {
                                decodeFrame(image)?.let { text ->
                                    handled = true
                                    previewView.post { onResult(text) }
                                }
                            }
                            image.close()
                        }

                        runCatching {
                            provider.unbindAll()
                            provider.bindToLifecycle(
                                lifecycleOwner,
                                CameraSelector.DEFAULT_BACK_CAMERA,
                                preview,
                                analysis,
                            )
                        }
                    }, ContextCompat.getMainExecutor(viewContext))

                    previewView
                },
            )

            // Рамка прицела
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(250.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(Color.White.copy(alpha = 0.10f))
            )

            Column(
                modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    "Наведите на QR-код из Amnezia",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                )
                TextButton(onClick = onClose) {
                    Text("Отмена", color = Color.White)
                }
            }
        } else {
            Column(
                modifier = Modifier.align(Alignment.Center).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    "Нужен доступ к камере, чтобы прочитать QR-код",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                )
                Button(onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) }) {
                    Text("Разрешить")
                }
                TextButton(onClick = onClose) {
                    Text("Закрыть", color = Color.White)
                }
            }
        }
    }
}

private val decodeHints: Map<DecodeHintType, Any> = EnumMap<DecodeHintType, Any>(DecodeHintType::class.java).apply {
    put(DecodeHintType.TRY_HARDER, true)
}

/** Кадр с камеры приходит в формате яркости — ZXing именно его и ждёт. */
private fun decodeFrame(image: ImageProxy): String? {
    return try {
        val buffer = image.planes[0].buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)

        val source = PlanarYUVLuminanceSource(
            bytes,
            image.planes[0].rowStride,
            image.height,
            0,
            0,
            image.width.coerceAtMost(image.planes[0].rowStride),
            image.height,
            false,
        )
        MultiFormatReader().decode(BinaryBitmap(HybridBinarizer(source)), decodeHints).text
    } catch (error: Exception) {
        null
    }
}

/** Чтение QR с картинки: снимок экрана с кодом из Amnezia на этом же телефоне. */
fun decodeQrFromImage(context: Context, uri: Uri): String? {
    return try {
        val bitmap = context.contentResolver.openInputStream(uri).use { stream ->
            BitmapFactory.decodeStream(stream)
        } ?: return null

        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val source = RGBLuminanceSource(bitmap.width, bitmap.height, pixels)
        MultiFormatReader().decode(BinaryBitmap(HybridBinarizer(source)), decodeHints).text
    } catch (error: Exception) {
        null
    }
}
