package ru.carpanel

import android.Manifest
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ru.carpanel.apps.AppCatalog
import ru.carpanel.apps.AppEntry
import ru.carpanel.data.Store
import ru.carpanel.drive.SpeedTracker
import ru.carpanel.media.MediaHub
import ru.carpanel.model.Defaults
import ru.carpanel.model.Grid
import ru.carpanel.model.Tile
import ru.carpanel.model.TileKind
import ru.carpanel.ui.PanelActions
import ru.carpanel.ui.PanelScreen
import ru.carpanel.ui.PanelTheme
import ru.carpanel.widgets.WidgetHostController

private const val REQUEST_BIND = 1001
private const val REQUEST_CONFIGURE = 1002

/** Главный и единственный экран: сама панель. */
class MainActivity : ComponentActivity() {

    private lateinit var store: Store
    private lateinit var catalog: AppCatalog
    private lateinit var media: MediaHub
    private lateinit var widgets: WidgetHostController
    private lateinit var speed: SpeedTracker

    /** Номер виджета, который сейчас привязывается или настраивается. */
    private var pendingWidgetId = 0

    private val locationRequest = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) {
        speed.start()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val app = PanelApp.of(this)
        store = app.store
        catalog = app.catalog
        media = app.media
        widgets = WidgetHostController(this)
        speed = SpeedTracker(this)

        applyKeepScreenOn(store.settings.keepScreenOn)

        val panelActions = actions()

        setContent {
            PanelTheme {
                val config by store.config.collectAsStateWithLifecycle()
                val snapshot by speed.state.collectAsStateWithLifecycle()

                PanelScreen(
                    config = config,
                    speed = snapshot,
                    catalog = catalog,
                    media = media,
                    widgets = widgets,
                    actions = panelActions,
                )
            }
        }
    }

    override fun onStart() {
        super.onStart()
        widgets.start()
        speed.start()
    }

    override fun onStop() {
        super.onStop()
        widgets.stop()
        speed.stop()
    }

    private fun actions() = PanelActions(
        onMove = { id, x, y -> store.updateBoard { Grid.move(it, id, x, y) } },
        onResize = { id, w, h -> store.updateBoard { Grid.resize(it, id, w, h) } },
        onRemove = ::removeTile,
        onLaunch = { tile ->
            if (!catalog.launch(tile)) {
                toast("Не удалось открыть: программа не установлена")
            }
        },
        onAddApp = ::addApp,
        onAddBuiltin = ::addBuiltin,
        onPickWidget = ::pickWidget,
        onResetTrip = { speed.resetTrip() },
        onRequestLocation = {
            locationRequest.launch(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            )
        },
        onNotificationAccess = {
            runCatching { startActivity(media.accessSettingsIntent()) }
                .onFailure { toast("Эта прошивка не открывает настройки доступа к уведомлениям") }
        },
        onColumns = { columns -> store.updateBoard { Grid.withColumns(it, columns) } },
        onRows = { rows -> store.updateBoard { it.copy(rows = rows.coerceIn(1, 6)) } },
        onKeepScreenOn = { on ->
            store.updateSettings { it.copy(keepScreenOn = on) }
            applyKeepScreenOn(on)
        },
        onMiles = { miles -> store.updateSettings { it.copy(miles = miles) } },
        onHomeScreen = ::setHomeScreen,
        onResetBoard = ::resetBoard,
    )

    private fun removeTile(id: Long) {
        val tile = store.board.tiles.firstOrNull { it.id == id }
        if (tile?.kind == TileKind.WIDGET) widgets.release(tile.widgetId)
        store.updateBoard { Grid.remove(it, id) }
    }

    private fun addApp(entry: AppEntry) {
        store.updateBoard { board ->
            Grid.add(
                board,
                Tile(
                    id = 0,
                    kind = TileKind.APP,
                    x = 0,
                    y = 0,
                    packageName = entry.packageName,
                    className = entry.className,
                    label = entry.label,
                ),
            )
        }
    }

    private fun addBuiltin(kind: TileKind) {
        val size = when (kind) {
            TileKind.SPEED -> 2 to 2
            TileKind.TRIP -> 1 to 2
            TileKind.MEDIA -> 2 to 1
            else -> 1 to 1
        }
        store.updateBoard { board ->
            Grid.add(board, Tile(id = 0, kind = kind, x = 0, y = 0, w = size.first, h = size.second))
        }
    }

    /** Шаг первый: просим у системы номер и согласие на привязку виджета. */
    private fun pickWidget(info: AppWidgetProviderInfo) {
        val widgetId = widgets.allocateId()
        if (widgetId <= 0) {
            toast("Система не выдала место под виджет")
            return
        }
        pendingWidgetId = widgetId

        if (widgets.bindQuietly(widgetId, info)) {
            afterBind(widgetId)
            return
        }

        val started = runCatching {
            startActivityForResult(widgets.bindRequestIntent(widgetId, info), REQUEST_BIND)
            true
        }.getOrDefault(false)

        if (!started) {
            widgets.release(widgetId)
            toast("Прошивка не разрешает добавлять чужие виджеты")
        }
    }

    /** Шаг второй: если у виджета есть свои настройки — открываем их. */
    private fun afterBind(widgetId: Int) {
        val info = widgets.info(widgetId)
        if (widgets.needsConfigure(info) && widgets.configure(this, widgetId, REQUEST_CONFIGURE)) return
        addWidgetTile(widgetId)
    }

    /** Шаг третий: виджет готов — кладём его на панель. */
    private fun addWidgetTile(widgetId: Int) {
        val info = widgets.info(widgetId)
        val (w, h) = Grid.cellsFor(info?.minWidth ?: 0, info?.minHeight ?: 0)
        store.updateBoard { board ->
            Grid.add(
                board,
                Tile(
                    id = 0,
                    kind = TileKind.WIDGET,
                    x = 0,
                    y = 0,
                    w = w,
                    h = h,
                    widgetId = widgetId,
                    packageName = info?.provider?.packageName,
                ),
            )
        }
        pendingWidgetId = 0
    }

    @Deprecated("Системные окна привязки и настройки виджета отвечают только сюда")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)

        val widgetId = data?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, pendingWidgetId)
            ?.takeIf { it > 0 }
            ?: pendingWidgetId
        if (widgetId <= 0) return

        when (requestCode) {
            REQUEST_BIND -> if (resultCode == RESULT_OK) afterBind(widgetId) else cancelWidget(widgetId)
            REQUEST_CONFIGURE -> if (resultCode == RESULT_OK) addWidgetTile(widgetId) else cancelWidget(widgetId)
        }
    }

    private fun cancelWidget(widgetId: Int) {
        widgets.release(widgetId)
        pendingWidgetId = 0
    }

    private fun resetBoard() {
        store.board.tiles
            .filter { it.kind == TileKind.WIDGET }
            .forEach { widgets.release(it.widgetId) }
        store.updateBoard { Defaults.board() }
    }

    /** Включить или выключить ярлык домашнего экрана. */
    private fun setHomeScreen(enabled: Boolean) {
        val alias = ComponentName(this, "ru.carpanel.HomeAlias")
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        val done = runCatching {
            packageManager.setComponentEnabledSetting(alias, state, PackageManager.DONT_KILL_APP)
        }.isSuccess

        if (!done) {
            toast("Прошивка не разрешает менять домашний экран")
            return
        }
        store.updateSettings { it.copy(homeScreen = enabled) }
        if (enabled) toast("Нажмите кнопку «домой» и выберите «Панель L9»")
    }

    private fun applyKeepScreenOn(on: Boolean) {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun toast(text: String) {
        Toast.makeText(this, text, Toast.LENGTH_LONG).show()
    }
}
