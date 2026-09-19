package ru.carpanel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.carpanel.model.Board
import ru.carpanel.model.Defaults
import ru.carpanel.model.Grid
import ru.carpanel.model.Tile
import ru.carpanel.model.TileKind

class GridTest {

    private fun tile(id: Long, x: Int, y: Int, w: Int = 1, h: Int = 1) =
        Tile(id = id, kind = TileKind.CLOCK, x = x, y = y, w = w, h = h)

    @Test
    fun `первая плитка встаёт в левый верхний угол`() {
        val board = Grid.add(Board(columns = 4, rows = 2), tile(0, 0, 0))
        val placed = board.tiles.single()
        assertEquals(0, placed.x)
        assertEquals(0, placed.y)
        assertEquals(1L, placed.id)
    }

    @Test
    fun `занятое место обходится стороной`() {
        var board = Board(columns = 3, rows = 2, tiles = listOf(tile(1, 0, 0)))
        board = Grid.add(board, tile(0, 0, 0))
        val added = board.tiles.last()
        assertEquals(1, added.x)
        assertEquals(0, added.y)
    }

    @Test
    fun `широкая плитка переносится на новый ряд`() {
        var board = Board(columns = 3, rows = 2, tiles = listOf(tile(1, 0, 0, w = 2)))
        board = Grid.add(board, tile(0, 0, 0, w = 2))
        val added = board.tiles.last()
        assertEquals(0, added.x)
        assertEquals(1, added.y)
    }

    @Test
    fun `плитка не вылезает за правый край`() {
        val board = Board(columns = 3, rows = 2, tiles = listOf(tile(1, 0, 0, w = 2)))
        assertFalse(Grid.fits(board, tile(2, 2, 0, w = 2)))
        assertTrue(Grid.fits(board, tile(2, 2, 0, w = 1)))
    }

    @Test
    fun `переезд на чужое место отменяется`() {
        val board = Board(
            columns = 4,
            rows = 2,
            tiles = listOf(tile(1, 0, 0), tile(2, 1, 0)),
        )
        val after = Grid.move(board, 2, 0, 0)
        assertEquals(board, after)
    }

    @Test
    fun `переезд на свободное место сохраняется`() {
        val board = Board(columns = 4, rows = 2, tiles = listOf(tile(1, 0, 0)))
        val after = Grid.move(board, 1, 3, 1)
        val moved = after.tiles.single()
        assertEquals(3, moved.x)
        assertEquals(1, moved.y)
    }

    @Test
    fun `переезд за край прижимается к краю`() {
        val board = Board(columns = 4, rows = 2, tiles = listOf(tile(1, 0, 0, w = 2)))
        val after = Grid.move(board, 1, 9, -3)
        val moved = after.tiles.single()
        assertEquals(2, moved.x)
        assertEquals(0, moved.y)
    }

    @Test
    fun `размер больше сетки не даётся`() {
        val board = Board(columns = 3, rows = 2, tiles = listOf(tile(1, 0, 0)))
        val after = Grid.resize(board, 1, 9, 9)
        val resized = after.tiles.single()
        assertEquals(3, resized.w)
        assertEquals(Grid.MAX_TILE_SIDE, resized.h)
    }

    @Test
    fun `рост плитки на занятого соседа отменяется`() {
        val board = Board(columns = 4, rows = 2, tiles = listOf(tile(1, 0, 0), tile(2, 1, 0)))
        val after = Grid.resize(board, 1, 2, 1)
        assertEquals(board, after)
    }

    @Test
    fun `после сужения сетки все плитки остаются`() {
        val board = Defaults.board()
        val narrow = Grid.withColumns(board, 3)
        assertEquals(3, narrow.columns)
        assertEquals(board.tiles.size, narrow.tiles.size)
        assertTrue(narrow.tiles.all { it.right <= 3 })
        assertTrue(narrow.tiles.all { placed -> narrow.tiles.none { it.id != placed.id && it.overlaps(placed) } })
    }

    @Test
    fun `заводская раскладка непротиворечива`() {
        val board = Defaults.board()
        assertTrue(board.tiles.all { Grid.fits(board, it) })
        assertEquals(3, Grid.visibleRows(board))
    }

    @Test
    fun `удаление убирает только свою плитку`() {
        val board = Board(columns = 4, rows = 2, tiles = listOf(tile(1, 0, 0), tile(2, 1, 0)))
        val after = Grid.remove(board, 1)
        assertEquals(listOf(2L), after.tiles.map { it.id })
    }

    @Test
    fun `размер чужого виджета считается по клеткам`() {
        assertEquals(1 to 1, Grid.cellsFor(0, 0))
        assertEquals(1 to 1, Grid.cellsFor(110, 40))
        assertEquals(2 to 1, Grid.cellsFor(300, 160))
        assertEquals(Grid.MAX_TILE_SIDE to Grid.MAX_TILE_SIDE, Grid.cellsFor(2000, 2000))
    }
}
