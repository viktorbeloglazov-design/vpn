package ru.carpanel.model

/**
 * Раскладка плиток по сетке.
 *
 * Здесь нет ни одного обращения к Android: чистая арифметика, которую
 * проверяют обычные тесты. Экран только рисует то, что решено тут.
 */
object Grid {

    const val MIN_COLUMNS = 2
    const val MAX_COLUMNS = 8
    const val MAX_TILE_SIDE = 4

    /** Номер для новой плитки: на единицу больше самого большого занятого. */
    fun nextId(board: Board): Long = (board.tiles.maxOfOrNull { it.id } ?: 0L) + 1L

    /** Сколько рядов занято плитками. */
    fun usedRows(board: Board): Int = board.tiles.maxOfOrNull { it.bottom } ?: 0

    /** Сколько рядов рисовать: заданное в настройках, но не меньше занятого. */
    fun visibleRows(board: Board): Int = maxOf(board.rows, usedRows(board), 1)

    /** Помещается ли плитка: не вылезает за края и ни с кем не пересекается. */
    fun fits(board: Board, tile: Tile): Boolean {
        if (tile.w < 1 || tile.h < 1) return false
        if (tile.x < 0 || tile.y < 0) return false
        if (tile.right > board.columns) return false
        return board.tiles.none { it.id != tile.id && it.overlaps(tile) }
    }

    /**
     * Первое свободное место под плитку размером [w] × [h].
     *
     * Идём слева направо, сверху вниз — как читают текст. Место найдётся всегда:
     * если ряды кончились, плитка встаёт в новый ряд под всеми остальными.
     */
    fun freeSlot(board: Board, w: Int, h: Int, ignoreId: Long? = null): Pair<Int, Int> {
        val width = w.coerceIn(1, board.columns)
        val others = board.tiles.filter { it.id != ignoreId }
        val probe = Board(board.columns, board.rows, others)
        for (y in 0..usedRows(probe)) {
            for (x in 0..(board.columns - width)) {
                val candidate = Tile(id = -1L, kind = TileKind.CLOCK, x = x, y = y, w = width, h = h)
                if (fits(probe, candidate)) return x to y
            }
        }
        return 0 to usedRows(probe)
    }

    /** Добавить плитку: на своё место, если оно свободно, иначе на первое свободное. */
    fun add(board: Board, tile: Tile): Board {
        val id = if (tile.id > 0) tile.id else nextId(board)
        val width = tile.w.coerceIn(1, minOf(board.columns, MAX_TILE_SIDE))
        val height = tile.h.coerceIn(1, MAX_TILE_SIDE)
        val wanted = tile.copy(id = id, w = width, h = height)
        val placed = if (fits(board, wanted)) {
            wanted
        } else {
            val (x, y) = freeSlot(board, width, height)
            wanted.copy(x = x, y = y)
        }
        return board.copy(tiles = board.tiles + placed)
    }

    /** Убрать плитку. */
    fun remove(board: Board, id: Long): Board =
        board.copy(tiles = board.tiles.filterNot { it.id == id })

    /**
     * Передвинуть плитку в клетку [x], [y].
     *
     * Если там занято или это за краем — панель остаётся прежней: плитка
     * просто вернётся на старое место, ничего не потерявшись.
     */
    fun move(board: Board, id: Long, x: Int, y: Int): Board {
        val tile = board.tiles.firstOrNull { it.id == id } ?: return board
        val moved = tile.copy(
            x = x.coerceIn(0, board.columns - tile.w),
            y = maxOf(0, y),
        )
        if (!fits(board, moved)) return board
        return board.copy(tiles = board.tiles.map { if (it.id == id) moved else it })
    }

    /** Поменять размер плитки. Если новая площадь заезжает на соседей — отказ. */
    fun resize(board: Board, id: Long, w: Int, h: Int): Board {
        val tile = board.tiles.firstOrNull { it.id == id } ?: return board
        val width = w.coerceIn(1, minOf(board.columns, MAX_TILE_SIDE))
        val height = h.coerceIn(1, MAX_TILE_SIDE)
        val resized = tile.copy(
            w = width,
            h = height,
            x = tile.x.coerceAtMost(board.columns - width),
        )
        if (!fits(board, resized)) return board
        return board.copy(tiles = board.tiles.map { if (it.id == id) resized else it })
    }

    /**
     * Держать на панели ровно одну плитку такого рода.
     *
     * Так работает переключатель набора программ: включили — плитка
     * появилась, выключили — исчезла, а остальная раскладка не тронута.
     */
    fun ensureTile(board: Board, kind: TileKind, present: Boolean, w: Int = 1, h: Int = 1): Board {
        val existing = board.tiles.filter { it.kind == kind }
        if (!present) return board.copy(tiles = board.tiles.filterNot { it.kind == kind })
        if (existing.isNotEmpty()) return board
        return add(board, Tile(id = 0, kind = kind, x = 0, y = 0, w = w, h = h))
    }

    /** Сторона клетки в точках: под неё считается, сколько места просит чужой виджет. */
    const val CELL_DP = 170

    /**
     * Сколько клеток просит виджет со своими наименьшими размерами.
     *
     * Меньше клетки не бывает, больше четырёх — не помещается на экран.
     */
    fun cellsFor(minWidthDp: Int, minHeightDp: Int): Pair<Int, Int> {
        fun cells(size: Int): Int {
            if (size <= 0) return 1
            return ((size + CELL_DP - 1) / CELL_DP).coerceIn(1, MAX_TILE_SIDE)
        }
        return cells(minWidthDp) to cells(minHeightDp)
    }

    /**
     * Сменить число столбцов и переложить плитки заново.
     *
     * Порядок сохраняется — сверху вниз и слева направо, — поэтому после
     * сужения сетки панель выглядит так же, только уже.
     */
    fun withColumns(board: Board, columns: Int): Board {
        val width = columns.coerceIn(MIN_COLUMNS, MAX_COLUMNS)
        val ordered = board.tiles.sortedWith(compareBy({ it.y }, { it.x }))
        var result = board.copy(columns = width, tiles = emptyList())
        for (tile in ordered) {
            val fitted = tile.copy(w = tile.w.coerceAtMost(width))
            val (x, y) = freeSlot(result, fitted.w, fitted.h)
            result = result.copy(tiles = result.tiles + fitted.copy(x = x, y = y))
        }
        return result.copy(rows = maxOf(board.rows, 1))
    }
}
