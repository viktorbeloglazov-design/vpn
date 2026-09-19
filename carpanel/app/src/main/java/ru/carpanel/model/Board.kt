package ru.carpanel.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Что показывает плитка. */
@Serializable
enum class TileKind {
    /** Ярлык установленной программы: Яндекс Навигатор, Яндекс Музыка и любая другая. */
    @SerialName("app") APP,

    /** Настоящий системный виджет чужой программы, выданный через AppWidgetHost. */
    @SerialName("widget") WIDGET,

    /** Спидометр по данным GPS. */
    @SerialName("speed") SPEED,

    /** Счётчик поездки: путь, средняя и наибольшая скорость, время. */
    @SerialName("trip") TRIP,

    /** Часы и дата. */
    @SerialName("clock") CLOCK,

    /** Управление тем, что играет сейчас: название трека и три кнопки. */
    @SerialName("media") MEDIA,
}

/**
 * Одна плитка на панели.
 *
 * Координаты и размер — в клетках сетки, отсчёт от левого верхнего угла.
 */
@Serializable
data class Tile(
    val id: Long,
    val kind: TileKind,
    val x: Int,
    val y: Int,
    val w: Int = 1,
    val h: Int = 1,
    /** Для [TileKind.APP] — что запускать. */
    val packageName: String? = null,
    val className: String? = null,
    /** Подпись, если хочется своя, а не из системы. */
    val label: String? = null,
    /** Для [TileKind.WIDGET] — номер, выданный AppWidgetHost. */
    val widgetId: Int = 0,
) {
    val right: Int get() = x + w
    val bottom: Int get() = y + h

    /** Пересекаются ли две плитки хотя бы одной клеткой. */
    fun overlaps(other: Tile): Boolean =
        x < other.right && other.x < right && y < other.bottom && other.y < bottom
}

/** Разложенная панель: сетка и плитки на ней. */
@Serializable
data class Board(
    val columns: Int = 5,
    val rows: Int = 3,
    val tiles: List<Tile> = emptyList(),
)

/** Настройки, общие для всей панели. */
@Serializable
data class Settings(
    /** Не гасить экран, пока панель открыта. */
    val keepScreenOn: Boolean = true,
    /** Скорость в милях вместо километров — на случай, если кому-то так привычнее. */
    val miles: Boolean = false,
    /** Панель предложена системе как домашний экран. */
    val homeScreen: Boolean = false,
)

/** Всё, что хранится между запусками. */
@Serializable
data class PanelConfig(
    val board: Board = Defaults.board(),
    val settings: Settings = Settings(),
)

/** Первая раскладка, которую видит хозяин машины сразу после установки. */
object Defaults {

    const val NAVIGATOR = "ru.yandex.yandexnavi"
    const val MUSIC = "ru.yandex.music"
    const val MAPS = "ru.yandex.yandexmaps"

    fun board(): Board = Board(
        columns = 5,
        rows = 3,
        tiles = listOf(
            Tile(id = 1, kind = TileKind.SPEED, x = 0, y = 0, w = 2, h = 2),
            Tile(id = 2, kind = TileKind.CLOCK, x = 2, y = 0, w = 1, h = 1),
            Tile(id = 3, kind = TileKind.MEDIA, x = 3, y = 0, w = 2, h = 1),
            Tile(id = 4, kind = TileKind.APP, x = 2, y = 1, w = 1, h = 1, packageName = NAVIGATOR, label = "Навигатор"),
            Tile(id = 5, kind = TileKind.APP, x = 3, y = 1, w = 1, h = 1, packageName = MUSIC, label = "Музыка"),
            Tile(id = 6, kind = TileKind.TRIP, x = 4, y = 1, w = 1, h = 2),
            Tile(id = 7, kind = TileKind.APP, x = 0, y = 2, w = 1, h = 1, packageName = MAPS, label = "Карты"),
        ),
    )
}
