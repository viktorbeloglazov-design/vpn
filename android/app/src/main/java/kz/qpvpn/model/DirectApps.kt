package kz.qpvpn.model

/**
 * Программы, которые обязаны работать мимо VPN — всегда, без исключений.
 *
 * Дело не в маршрутах: их адреса и так идут напрямую. Эти программы сами
 * проверяют, поднят ли на телефоне VPN, и отказываются работать, даже когда
 * их трафик туннеля не касается. МАХ показывает «Отключите VPN», банки и
 * госуслуги просят подтверждение или просто не пускают.
 *
 * Лечится это только одним способом: сказать системе, что туннель к этим
 * программам не относится. Тогда для них VPN не существует — ни в
 * маршрутах, ни в том, что им показывает Android.
 *
 * Совпадение ищется тремя способами сразу, чтобы МАХ попал в список в любом
 * виде: по точному имени пакета, по куску имени (на случай беты или
 * пересборки) и по названию на экране (на случай переименования).
 */
object DirectApps {

    /** Точные имена пакетов. */
    val packages: List<String> = listOf(
        // МАХ — ради него всё и затевалось.
        "ru.oneme.app",
        "ru.oneme.app.beta",
        "ru.ok.messages",              // ТамТам: тот же стек, то же поведение

        // Госуслуги и документы
        "ru.rostel",                   // Госуслуги
        "ru.gosuslugi.doc",            // Госуслуги Документы
        "ru.gosuslugi.goskey",         // Госключ
        "ru.fns.billsCheck",           // Проверка чеков ФНС
        "com.nalog.lkfl2",             // Налоги ФЛ

        // Банки и платежи
        "ru.sberbankmobile",           // СберБанк Онлайн
        "ru.sberbank.sbol",
        "com.idamob.tinkoff.android",  // Т-Банк
        "ru.vtb24.mobilebanking.android",
        "ru.alfabank.mobile.android",
        "ru.raiffeisennews",
        "ru.gazprombank.android.mobilebank.app",
        "ru.psbank.mobile",
        "ru.mkb.mobile",
        "ru.rshb.mbank",
        "ru.otpbank.mobile",
        "ru.nspk.mirpay",              // Mir Pay
        "ru.nspk.sbpay",               // СБПэй

        // Связь и госуслуги регионов
        "ru.mts.mymts",
        "ru.megafon.mlk",
        "ru.beeline.services",
        "ru.tele2.mytele2",
        "ru.mos.polis",                // ЕМИАС
        "ru.mos.mospolytech",
    )

    /**
     * Начала имён пакетов российских программ.
     *
     * Перечислять их поимённо бессмысленно: список никогда не будет полным,
     * а каждая пропущенная программа — это очередное «Отключите VPN».
     * Российской программе туннель и не нужен: её адреса и так идут
     * напрямую, так что мимо VPN она ничего не теряет.
     */
    val prefixes: List<String> = listOf("ru.")

    /**
     * Куски имени пакета.
     *
     * Первые четыре — чтобы МАХ опознался в любом виде: бета, сборка для
     * RuStore, предустановленная версия. Остальные — российские программы,
     * чьё имя начинается не с «ru.»: Т-Банк живёт в com.idamob, Wildberries
     * в com.wildberries.ru, Авито в com.avito.
     */
    val fragments: List<String> = listOf(
        // МАХ в любом написании
        "oneme",
        "max.messenger",
        "maxmessenger",
        "messenger.max",

        // Банки и платежи
        "sberbank",
        "tinkoff",
        "alfabank",
        "gazprombank",
        "raiffeisen",
        "rosbank",
        "sovcombank",
        "uralsib",
        "otpbank",
        "psbank",
        "vtb",
        "mirpay",
        "sbpay",
        "nspk",

        // Государство
        "gosuslugi",
        "goskey",
        "nalog",

        // Торговля и сервисы
        "wildberries",
        "ozon",
        "avito",
        "yandex",
        "vkontakte",
        "megafon",
        "beeline",
        "tele2",
    )

    /** Окончания имён: так пишутся com.wildberries.ru и подобные. */
    val suffixes: List<String> = listOf(".ru")

    /**
     * Названия на экране. Сравниваются целиком, без учёта регистра, —
     * иначе под правило попали бы игры и всё, где встречается «max».
     *
     * Латиница и кириллица обе: на витринах МАХ пишут и так, и так.
     */
    val labels: List<String> = listOf(
        "max",
        "мах",
        "max — мессенджер",
        "max мессенджер",
    )

    /**
     * Имена пакетов строчными — по ним идёт сравнение.
     *
     * В самом списке регистр сохранён как есть: система различает его, и
     * «ru.fns.billsCheck» с маленькой «c» она не найдёт.
     */
    private val lowercased: Set<String> by lazy { packages.map { it.lowercase() }.toSet() }

    /** Подходит ли установленная программа под железное правило. */
    fun matches(packageName: String, label: String): Boolean {
        val name = packageName.trim().lowercase()
        if (name in lowercased) return true
        if (prefixes.any { name.startsWith(it) }) return true
        if (suffixes.any { name.endsWith(it) }) return true
        if (fragments.any { name.contains(it) }) return true
        return label.trim().lowercase() in labels
    }

    val count: Int get() = packages.size
}
