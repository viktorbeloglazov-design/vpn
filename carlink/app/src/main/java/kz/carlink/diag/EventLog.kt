package kz.carlink.diag

import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Журнал подключения.
 *
 * Машину не подключить к отладчику, поэтому единственный способ понять, на чём
 * всё встало, — подробная запись каждого шага. Её можно скопировать целиком и
 * отправить себе.
 */
object EventLog {

    private const val MAX_LINES = 600

    private val format = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault())
    private val _lines = MutableStateFlow<List<String>>(emptyList())
    val lines: StateFlow<List<String>> = _lines

    fun log(text: String) {
        Log.i("CarLink", text)
        val stamp = format.format(Date())
        val entry = text.lineSequence().mapIndexed { index, line ->
            if (index == 0) "$stamp  $line" else "             $line"
        }.joinToString("\n")
        _lines.value = (_lines.value + entry).takeLast(MAX_LINES)
    }

    fun clear() {
        _lines.value = emptyList()
    }

    fun asText(): String = _lines.value.joinToString("\n")
}
