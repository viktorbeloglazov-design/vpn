package ru.carpanel.apps

/**
 * Русские названия для плиток.
 *
 * Система машины приезжает с китайскими и английскими подписями. Меню самой
 * прошивки программа переписать не может, но всё, что она показывает сама —
 * плитки и список выбора, — переводит по этому словарю. Чего нет в словаре,
 * хозяин машины переименовывает руками.
 */
object Russify {

    private val chinese = mapOf(
        "设置" to "Настройки",
        "车辆设置" to "Настройки автомобиля",
        "系统设置" to "Настройки системы",
        "系统" to "Система",
        "音乐" to "Музыка",
        "电话" to "Телефон",
        "通讯录" to "Контакты",
        "信息" to "Сообщения",
        "收音机" to "Радио",
        "电台" to "Радиостанции",
        "视频" to "Видео",
        "影音" to "Мультимедиа",
        "导航" to "Навигация",
        "地图" to "Карты",
        "相机" to "Камера",
        "图库" to "Галерея",
        "相册" to "Фотоальбом",
        "文件管理" to "Файлы",
        "文件管理器" to "Файлы",
        "应用商店" to "Магазин программ",
        "应用" to "Программы",
        "日历" to "Календарь",
        "天气" to "Погода",
        "时钟" to "Часы",
        "计算器" to "Калькулятор",
        "录音机" to "Диктофон",
        "行车记录仪" to "Видеорегистратор",
        "空调" to "Климат",
        "座椅" to "Сиденья",
        "充电" to "Зарядка",
        "能耗" to "Расход энергии",
        "油耗" to "Расход топлива",
        "里程" to "Пробег",
        "胎压" to "Давление в шинах",
        "保养" to "Обслуживание",
        "停车" to "Парковка",
        "浏览器" to "Браузер",
        "下载" to "Загрузки",
        "游戏" to "Игры",
        "新闻" to "Новости",
        "语音助手" to "Голосовой помощник",
        "车控" to "Управление автомобилем",
        "主页" to "Главная",
        "我的" to "Профиль",
        "账户" to "Учётная запись",
        "帮助" to "Помощь",
        "关于" to "О системе",
        "升级" to "Обновление",
        "用户手册" to "Руководство",
        "安全" to "Безопасность",
        "屏幕" to "Экран",
        "亮度" to "Яркость",
        "声音" to "Звук",
        "音量" to "Громкость",
        "网络" to "Сеть",
        "时间" to "Время",
        "语言" to "Язык",
        "输入法" to "Клавиатура",
        "键盘" to "Клавиатура",
        "通知" to "Уведомления",
        "权限" to "Разрешения",
        "存储" to "Память",
        "电池" to "Батарея",
        "儿童模式" to "Детский режим",
    )

    private val english = mapOf(
        "settings" to "Настройки",
        "system settings" to "Настройки системы",
        "car settings" to "Настройки автомобиля",
        "vehicle" to "Автомобиль",
        "system" to "Система",
        "music" to "Музыка",
        "phone" to "Телефон",
        "dialer" to "Телефон",
        "contacts" to "Контакты",
        "messages" to "Сообщения",
        "messaging" to "Сообщения",
        "radio" to "Радио",
        "video" to "Видео",
        "videos" to "Видео",
        "media" to "Мультимедиа",
        "navigation" to "Навигация",
        "maps" to "Карты",
        "camera" to "Камера",
        "gallery" to "Галерея",
        "photos" to "Фотографии",
        "files" to "Файлы",
        "file manager" to "Файлы",
        "app store" to "Магазин программ",
        "app market" to "Магазин программ",
        "apps" to "Программы",
        "calendar" to "Календарь",
        "weather" to "Погода",
        "clock" to "Часы",
        "calculator" to "Калькулятор",
        "recorder" to "Диктофон",
        "voice recorder" to "Диктофон",
        "dashcam" to "Видеорегистратор",
        "dash cam" to "Видеорегистратор",
        "browser" to "Браузер",
        "downloads" to "Загрузки",
        "notes" to "Заметки",
        "games" to "Игры",
        "news" to "Новости",
        "help" to "Помощь",
        "about" to "О системе",
        "update" to "Обновление",
        "updater" to "Обновление",
        "voice assistant" to "Голосовой помощник",
        "assistant" to "Голосовой помощник",
        "climate" to "Климат",
        "charging" to "Зарядка",
        "energy" to "Расход энергии",
        "profile" to "Профиль",
        "account" to "Учётная запись",
        "home" to "Главная",
        "security" to "Безопасность",
        "display" to "Экран",
        "sound" to "Звук",
        "volume" to "Громкость",
        "network" to "Сеть",
        "language" to "Язык",
        "keyboard" to "Клавиатура",
        "notifications" to "Уведомления",
        "permissions" to "Разрешения",
        "storage" to "Память",
        "battery" to "Батарея",
    )

    /** Есть ли для такой подписи русский перевод. */
    fun has(label: String?): Boolean = lookup(label) != null

    /** Русское название, если оно известно; иначе подпись остаётся как была. */
    fun translate(label: String?): String {
        val original = label?.trim().orEmpty()
        return lookup(original) ?: original
    }

    /**
     * Подпись плитки с учётом всего, что знаем.
     *
     * Сначала список известных программ (Яндекс Навигатор и соседи), затем
     * словарь, и в последнюю очередь — то, что вернула сама система.
     */
    fun label(packageName: String?, fromSystem: String): String =
        KnownApps.label(packageName) ?: translate(fromSystem)

    private fun lookup(label: String?): String? {
        val original = label?.trim().orEmpty()
        if (original.isEmpty()) return null
        chinese[original]?.let { return it }
        english[original.lowercase()]?.let { return it }
        return null
    }
}
