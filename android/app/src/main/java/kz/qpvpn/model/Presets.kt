package kz.qpvpn.model

/**
 * Готовые наборы правил.
 *
 * Собраны под работу из России через зарубежный сервер: одни сервисы нужно
 * завернуть в туннель, потому что они не отвечают российским адресам, другие —
 * наоборот, оставить на прямом канале, иначе банк или маркетплейс увидит
 * смену страны и попросит подтверждение.
 */
data class RulePreset(
    val id: String,
    val title: String,
    val subtitle: String,
    val direction: PresetDirection,
    val values: List<Pair<RuleKind, String>>,
) {
    val count: Int get() = values.size

    fun rules(): List<RoutingRule> = values.map { (kind, value) ->
        RoutingRule(kind = kind, value = value, note = title)
    }
}

/** Куда набор направляет трафик. */
enum class PresetDirection {
    /** Через туннель — режим «только правила через VPN». */
    THROUGH_VPN,

    /** Мимо туннеля — режим «всё через VPN, кроме правил». */
    DIRECT;

    val title: String
        get() = if (this == THROUGH_VPN) "через VPN" else "напрямую"

    val mode: TunnelMode
        get() = if (this == THROUGH_VPN) TunnelMode.INCLUDE else TunnelMode.EXCLUDE
}

object Presets {

    private fun domains(vararg hosts: String) = hosts.map { RuleKind.DOMAIN to it }

    /** Наборы для туннеля: сервисы, которые не работают с российских адресов. */
    val throughVpn: List<RulePreset> = listOf(
        RulePreset(
            id = "ai",
            title = "Нейросети",
            subtitle = "ChatGPT, Claude, Gemini, Midjourney — почти все закрыты для адресов РФ",
            direction = PresetDirection.THROUGH_VPN,
            values = domains(
                "openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com",
                "anthropic.com", "claude.ai",
                "gemini.google.com", "bard.google.com", "aistudio.google.com",
                "perplexity.ai", "midjourney.com", "huggingface.co",
                "copilot.microsoft.com", "x.ai", "grok.com", "mistral.ai",
                "runwayml.com", "elevenlabs.io", "suno.com",
            ),
        ),
        RulePreset(
            id = "social",
            title = "Соцсети",
            subtitle = "Instagram, Facebook, X, LinkedIn и их сети доставки",
            direction = PresetDirection.THROUGH_VPN,
            values = domains(
                "instagram.com", "cdninstagram.com", "facebook.com", "fb.com",
                "fbcdn.net", "messenger.com", "threads.net",
                "twitter.com", "x.com", "twimg.com", "t.co",
                "linkedin.com", "licdn.com", "pinterest.com", "reddit.com",
                "redditstatic.com", "tumblr.com",
            ),
        ),
        RulePreset(
            id = "video",
            title = "Видео и музыка",
            subtitle = "YouTube, Twitch, Netflix, Spotify",
            direction = PresetDirection.THROUGH_VPN,
            values = domains(
                "youtube.com", "youtu.be", "ytimg.com", "googlevideo.com", "ggpht.com",
                "twitch.tv", "ttvnw.net", "jtvnw.net",
                "netflix.com", "nflxvideo.net", "nflximg.net",
                "spotify.com", "scdn.co", "spotifycdn.com",
                "vimeo.com", "soundcloud.com", "deezer.com",
            ),
        ),
        RulePreset(
            id = "messengers",
            title = "Мессенджеры",
            subtitle = "Discord, Signal, Viber, Skype",
            direction = PresetDirection.THROUGH_VPN,
            values = domains(
                "discord.com", "discordapp.com", "discordapp.net", "discord.gg",
                "signal.org", "signal.art", "viber.com", "skype.com",
                "slack.com", "slack-edge.com",
            ),
        ),
        RulePreset(
            id = "work",
            title = "Рабочие сервисы",
            subtitle = "GitHub, Notion, Figma, Atlassian, магазины приложений",
            direction = PresetDirection.THROUGH_VPN,
            values = domains(
                "github.com", "githubusercontent.com", "githubassets.com", "github.io",
                "gitlab.com", "docker.com", "docker.io", "npmjs.com",
                "jetbrains.com", "atlassian.com", "atlassian.net",
                "notion.so", "notion.site", "figma.com", "canva.com",
                "vercel.com", "netlify.app", "cloudflare.com",
                "medium.com", "stackoverflow.com", "patreon.com",
            ),
        ),
        RulePreset(
            id = "shopping-global",
            title = "Зарубежные покупки",
            subtitle = "Amazon, eBay, Shein и платёжные сервисы",
            direction = PresetDirection.THROUGH_VPN,
            values = domains(
                "amazon.com", "amazon.de", "ebay.com", "shein.com",
                "paypal.com", "stripe.com", "wise.com", "revolut.com",
                "booking.com", "airbnb.com", "aliexpress.us",
            ),
        ),
    )

    /** Наборы для прямого канала: сервисы, которым нужен российский адрес. */
    val direct: List<RulePreset> = listOf(
        RulePreset(
            id = "ru-banks",
            title = "Банки РФ",
            subtitle = "Сбер, Т-Банк, Альфа, ВТБ и остальные — с зарубежного адреса блокируют вход",
            direction = PresetDirection.DIRECT,
            values = domains(
                "sberbank.ru", "sbrf.ru", "online.sberbank.ru", "sber.ru", "sberbank.com",
                "tbank.ru", "tinkoff.ru", "tinkoff.com",
                "alfabank.ru", "alfabank.com", "click.alfabank.ru",
                "vtb.ru", "online.vtb.ru", "gazprombank.ru", "gpb.ru",
                "raiffeisen.ru", "psbank.ru", "open.ru", "mkb.ru",
                "rshb.ru", "sovcombank.ru", "uralsib.ru", "rosbank.ru",
                "pochtabank.ru", "ozon.ru.bank", "yoomoney.ru", "qiwi.com",
            ),
        ),
        RulePreset(
            id = "ru-gov",
            title = "Госуслуги и налоговая",
            subtitle = "gosuslugi.ru, ФНС, ПФР, суды, закупки, Росреестр",
            direction = PresetDirection.DIRECT,
            values = domains(
                "gosuslugi.ru", "esia.gosuslugi.ru", "nalog.gov.ru", "nalog.ru",
                "lkul.nalog.ru", "egrul.nalog.ru", "service.nalog.ru",
                "pfr.gov.ru", "sfr.gov.ru", "fss.ru",
                "mos.ru", "cbr.ru", "fssp.gov.ru", "gibdd.ru",
                "rosreestr.gov.ru", "zakupki.gov.ru", "fedresurs.ru",
                "sudrf.ru", "arbitr.ru", "kad.arbitr.ru", "roskazna.gov.ru",
                "customs.gov.ru", "rospotrebnadzor.ru", "honestsign.ru",
            ),
        ),
        RulePreset(
            id = "ru-marketplaces",
            title = "Маркетплейсы",
            subtitle = "Кабинеты продавца Wildberries, Ozon, Яндекс Маркета, Авито",
            direction = PresetDirection.DIRECT,
            values = domains(
                "wildberries.ru", "seller.wildberries.ru", "wbstatic.net", "wbbasket.ru",
                "ozon.ru", "seller.ozon.ru", "ozone.ru", "ozonusercontent.com",
                "market.yandex.ru", "partner.market.yandex.ru",
                "megamarket.ru", "sbermegamarket.ru",
                "avito.ru", "avito.st", "lamoda.ru", "dns-shop.ru",
                "citilink.ru", "eldorado.ru", "mvideo.ru", "detmir.ru",
            ),
        ),
        RulePreset(
            id = "ru-services",
            title = "Яндекс, VK и почта",
            subtitle = "Такси, доставка, карты, Почта Mail.ru, VK, Дзен, Кинопоиск",
            direction = PresetDirection.DIRECT,
            values = domains(
                "yandex.ru", "ya.ru", "yandex.net", "yandex.com", "yastatic.net",
                "taxi.yandex.ru", "eda.yandex.ru", "lavka.yandex.ru",
                "mail.ru", "vk.com", "vk.ru", "userapi.com", "vk-cdn.net",
                "ok.ru", "dzen.ru", "rutube.ru", "kinopoisk.ru", "ivi.ru",
                "wink.ru", "premier.one", "smotrim.ru",
            ),
        ),
        RulePreset(
            id = "ru-telecom",
            title = "Связь и ЖКХ",
            subtitle = "МТС, Билайн, Мегафон, Теле2, оплата счетов",
            direction = PresetDirection.DIRECT,
            values = domains(
                "mts.ru", "beeline.ru", "megafon.ru", "tele2.ru", "yota.ru",
                "rt.ru", "domru.ru", "gis-zkh.ru", "dom.gosuslugi.ru",
                "mosenergosbyt.ru", "pgu.mos.ru",
            ),
        ),
        RulePreset(
            id = "ru-logistics",
            title = "Логистика",
            subtitle = "СДЭК, Почта России, Деловые Линии, ПЭК, Боксберри",
            direction = PresetDirection.DIRECT,
            values = domains(
                "cdek.ru", "pochta.ru", "russianpost.ru", "dellin.ru",
                "pecom.ru", "boxberry.ru", "baikalsr.ru", "kit.tk",
                "vezubr.ru", "gruzovichkof.ru",
            ),
        ),
        RulePreset(
            id = "cn-suppliers",
            title = "Китайские поставщики",
            subtitle = "1688, Alibaba, Taobao, WeChat — работают лучше напрямую",
            direction = PresetDirection.DIRECT,
            values = domains(
                "1688.com", "alibaba.com", "alicdn.com", "taobao.com", "tmall.com",
                "aliexpress.com", "aliexpress.ru", "wechat.com", "weixin.qq.com",
                "qq.com", "alipay.com", "dhgate.com", "made-in-china.com",
            ),
        ),
        RulePreset(
            id = "kz-services",
            title = "Сервисы Казахстана",
            subtitle = "Kaspi, Halyk, egov, Kolesa — если сервер стоит не в Казахстане",
            direction = PresetDirection.DIRECT,
            values = domains(
                "kaspi.kz", "halykbank.kz", "homebank.kz", "egov.kz", "gov.kz",
                "salyk.kz", "olx.kz", "kolesa.kz", "krisha.kz", "market.kz",
                "wildberries.kz", "beeline.kz", "kcell.kz", "tele2.kz",
            ),
        ),
        RulePreset(
            id = "local",
            title = "Локальная сеть",
            subtitle = "Принтеры, камеры, роутер — всегда мимо туннеля",
            direction = PresetDirection.DIRECT,
            values = listOf(
                RuleKind.CIDR to "10.0.0.0/8",
                RuleKind.CIDR to "172.16.0.0/12",
                RuleKind.CIDR to "192.168.0.0/16",
                RuleKind.CIDR to "169.254.0.0/16",
            ),
        ),
        RulePreset(
            id = "calls",
            title = "Видеозвонки",
            subtitle = "Zoom, Teams, Meet — напрямую качество обычно выше",
            direction = PresetDirection.DIRECT,
            values = domains(
                "zoom.us", "zoom.com", "teams.microsoft.com", "meet.google.com",
                "telemost.yandex.ru", "webinar.ru",
            ),
        ),
    )

    val all: List<RulePreset> get() = throughVpn + direct

    fun byId(id: String): RulePreset? = all.firstOrNull { it.id == id }
}
