package ru.carpanel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.carpanel.model.AppSet
import ru.carpanel.model.Board
import ru.carpanel.model.Defaults
import ru.carpanel.model.Grid
import ru.carpanel.model.TileKind

class AppSetTest {

    @Test
    fun `в наборе сразу лежат навигатор, музыка и карты`() {
        val set = AppSet()
        assertFalse(set.enabled)
        assertEquals(listOf(Defaults.NAVIGATOR, Defaults.MUSIC, Defaults.MAPS), set.packages)
    }

    @Test
    fun `одна и та же программа не добавляется дважды`() {
        val set = AppSet(packages = listOf(Defaults.MUSIC))
        assertEquals(listOf(Defaults.MUSIC), set.with(Defaults.MUSIC).packages)
        assertEquals(listOf(Defaults.MUSIC, Defaults.MAPS), set.with(Defaults.MAPS).packages)
    }

    @Test
    fun `пустое имя пакета в набор не попадает`() {
        val set = AppSet(packages = emptyList())
        assertTrue(set.with("   ").packages.isEmpty())
    }

    @Test
    fun `набор не растёт больше отведённых мест`() {
        var set = AppSet(packages = emptyList())
        repeat(AppSet.MAX + 3) { number -> set = set.with("ru.example.app$number") }
        assertEquals(AppSet.MAX, set.packages.size)
        assertEquals(AppSet.MAX, set.visible().size)
    }

    @Test
    fun `программа убирается из набора`() {
        val set = AppSet(packages = listOf(Defaults.NAVIGATOR, Defaults.MUSIC))
        assertEquals(listOf(Defaults.NAVIGATOR), set.without(Defaults.MUSIC).packages)
        assertEquals(2, set.without("ru.example.unknown").packages.size)
    }

    @Test
    fun `включение набора кладёт плитку на панель, выключение убирает`() {
        val board = Board(columns = 4, rows = 2)
        val withSet = Grid.ensureTile(board, TileKind.GROUP, present = true, w = 2, h = 1)
        assertEquals(1, withSet.tiles.count { it.kind == TileKind.GROUP })
        assertEquals(2, withSet.tiles.single().w)

        val again = Grid.ensureTile(withSet, TileKind.GROUP, present = true, w = 2, h = 1)
        assertEquals(1, again.tiles.count { it.kind == TileKind.GROUP })

        val without = Grid.ensureTile(again, TileKind.GROUP, present = false)
        assertTrue(without.tiles.none { it.kind == TileKind.GROUP })
    }

    @Test
    fun `выключение набора не трогает остальные плитки`() {
        val board = Grid.ensureTile(Defaults.board(), TileKind.GROUP, present = true, w = 2, h = 1)
        val without = Grid.ensureTile(board, TileKind.GROUP, present = false)
        assertEquals(Defaults.board().tiles.size, without.tiles.size)
    }
}
