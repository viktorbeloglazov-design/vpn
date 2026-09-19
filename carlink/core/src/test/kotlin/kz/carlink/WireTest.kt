package kz.carlink

import kz.carlink.proto.ProtoDump
import kz.carlink.proto.ProtoReader
import kz.carlink.proto.ProtoWriter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WireTest {

    @Test
    fun readsBackNumbersStringsAndNestedMessages() {
        val data = ProtoWriter()
            .int32(1, 7)
            .string(2, "Porsche Taycan")
            .bool(3, true)
            .message(4) {
                int32(1, 1280)
                int32(2, 720)
            }
            .varint(5, 9_000_000_000L)
            .toByteArray()

        var number = 0
        var text = ""
        var flag = false
        var width = 0
        var height = 0
        var big = 0L

        val reader = ProtoReader(data)
        while (reader.next()) {
            when (reader.field) {
                1 -> number = reader.int32()
                2 -> text = reader.string()
                3 -> flag = reader.bool()
                4 -> {
                    val nested = reader.nested()
                    while (nested.next()) {
                        when (nested.field) {
                            1 -> width = nested.int32()
                            2 -> height = nested.int32()
                        }
                    }
                }
                5 -> big = reader.varint()
            }
        }

        assertEquals(7, number)
        assertEquals("Porsche Taycan", text)
        assertTrue(flag)
        assertEquals(1280, width)
        assertEquals(720, height)
        assertEquals(9_000_000_000L, big)
    }

    @Test
    fun skipsUnreadFields() {
        val data = ProtoWriter()
            .string(1, "пропустим")
            .message(2) { int32(1, 5) }
            .int32(3, 42)
            .toByteArray()

        var last = 0
        val reader = ProtoReader(data)
        while (reader.next()) {
            if (reader.field == 3) last = reader.int32()
        }
        assertEquals(42, last)
    }

    @Test
    fun dumpShowsFieldNumbers() {
        val data = ProtoWriter().int32(1, 3).string(2, "PCM").toByteArray()
        val dump = ProtoDump.dump(data)
        assertTrue(dump, dump.contains("#1 = 3"))
        assertTrue(dump, dump.contains("#2 = \"PCM\""))
    }
}
