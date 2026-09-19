package ru.carpanel.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import ru.carpanel.model.Board
import ru.carpanel.model.Grid
import ru.carpanel.model.Tile
import ru.carpanel.model.TileKind
import kotlin.math.roundToInt

/**
 * Сетка панели.
 *
 * Клетки считаются от доступного места: сколько столбцов и рядов задано
 * в настройках, столько плитка и занимает. В режиме правки плитку можно
 * перетащить пальцем — она встанет в ближайшую свободную клетку.
 */
@Composable
fun BoardGrid(
    board: Board,
    editing: Boolean,
    modifier: Modifier = Modifier,
    gap: Dp = 12.dp,
    onMove: (Long, Int, Int) -> Unit,
    onResize: (Long, Int, Int) -> Unit,
    onRemove: (Long) -> Unit,
    onRename: (Tile) -> Unit = {},
    content: @Composable (Tile) -> Unit,
) {
    val rows = Grid.visibleRows(board)
    val columns = board.columns.coerceIn(Grid.MIN_COLUMNS, Grid.MAX_COLUMNS)

    BoxWithConstraints(modifier = modifier) {
        val cellWidth = (maxWidth - gap * (columns - 1)) / columns
        val cellHeight = (maxHeight - gap * (rows - 1)) / rows
        val density = LocalDensity.current
        val stepX = with(density) { (cellWidth + gap).toPx() }
        val stepY = with(density) { (cellHeight + gap).toPx() }

        var draggingId by remember { mutableStateOf<Long?>(null) }
        var dragOffset by remember { mutableStateOf(Offset.Zero) }

        for (tile in board.tiles) {
            key(tile.id) {
                val dragging = draggingId == tile.id
                val width = cellWidth * tile.w + gap * (tile.w - 1)
                val height = cellHeight * tile.h + gap * (tile.h - 1)

                Box(
                    modifier = Modifier
                        .offset(x = (cellWidth + gap) * tile.x, y = (cellHeight + gap) * tile.y)
                        .size(width = width, height = height)
                        .then(
                            if (dragging) {
                                Modifier
                                    .zIndex(2f)
                                    .offset { IntOffset(dragOffset.x.roundToInt(), dragOffset.y.roundToInt()) }
                            } else {
                                Modifier
                            }
                        )
                        .pointerInput(editing, tile.id, stepX, stepY) {
                            if (!editing) return@pointerInput
                            awaitEachGesture {
                                // Нажатие, которое не перехватила кнопка на плитке, —
                                // значит, плитку тянут.
                                val down = awaitFirstDown(requireUnconsumed = true)
                                draggingId = tile.id
                                dragOffset = Offset.Zero
                                var moved = Offset.Zero
                                while (true) {
                                    val event = awaitPointerEvent()
                                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                    if (change.changedToUpIgnoreConsumed()) {
                                        change.consume()
                                        break
                                    }
                                    moved += change.positionChange()
                                    change.consume()
                                    dragOffset = moved
                                }
                                draggingId = null
                                dragOffset = Offset.Zero
                                val dx = if (stepX > 0f) (moved.x / stepX).roundToInt() else 0
                                val dy = if (stepY > 0f) (moved.y / stepY).roundToInt() else 0
                                if (dx != 0 || dy != 0) onMove(tile.id, tile.x + dx, tile.y + dy)
                            }
                        },
                ) {
                    Box(modifier = Modifier.fillMaxSize().alpha(if (dragging) 0.85f else 1f)) {
                        content(tile)
                    }

                    if (editing) {
                        EditControls(
                            tile = tile,
                            columns = columns,
                            onResize = onResize,
                            onRemove = onRemove,
                            onRename = onRename,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
            }
        }
    }
}

/** Кнопки правки поверх плитки: убрать и поменять размер. */
@Composable
private fun EditControls(
    tile: Tile,
    columns: Int,
    onResize: (Long, Int, Int) -> Unit,
    onRemove: (Long) -> Unit,
    onRename: (Tile) -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.padding(6.dp)) {
        // Переименовать имеет смысл там, где подпись приходит от чужой
        // программы: её можно заменить русской.
        if (tile.kind == TileKind.APP) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer)
                    .clickable { onRename(tile) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "Аа",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
        }

        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .size(36.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.error)
                .clickable { onRemove(tile.id) },
            contentAlignment = Alignment.Center,
        ) {
            Text("✕", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onPrimary)
        }

        Row(
            modifier = Modifier.align(Alignment.BottomCenter),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            SizeButton("Ш−", enabled = tile.w > 1) { onResize(tile.id, tile.w - 1, tile.h) }
            SizeButton("Ш+", enabled = tile.w < minOf(columns, Grid.MAX_TILE_SIDE)) { onResize(tile.id, tile.w + 1, tile.h) }
            SizeButton("В−", enabled = tile.h > 1) { onResize(tile.id, tile.w, tile.h - 1) }
            SizeButton("В+", enabled = tile.h < Grid.MAX_TILE_SIDE) { onResize(tile.id, tile.w, tile.h + 1) }
        }
    }
}

@Composable
private fun SizeButton(label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(width = 46.dp, height = 34.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .alpha(if (enabled) 1f else 0.35f)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurface)
    }
}
