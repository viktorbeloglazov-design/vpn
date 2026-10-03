package kz.qpvpn.model

/**
 * Главный фильтр: всё, что не открывается с российского адреса.
 *
 * Это единственный переключатель, который нужен большинству. Когда он включён,
 * через туннель идут только перечисленные сервисы, а весь остальной интернет —
 * включая банки, госуслуги и маркетплейсы — остаётся на домашнем адресе.
 *
 * Список разбит на разделы для удобства чтения; в маршрутизацию он уходит
 * одним набором.
 */
object MasterFilter {

    data class Section(val title: String, val domains: List<String>)

    val sections: List<Section> = listOf(
        Section(
            "Нейросети",
            listOf(
                "openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "sora.com",
                "anthropic.com", "claude.ai", "claudeusercontent.com",
                "gemini.google.com", "aistudio.google.com", "bard.google.com", "deepmind.google",
                "perplexity.ai", "midjourney.com", "huggingface.co", "copilot.microsoft.com",
                "x.ai", "grok.com", "mistral.ai", "cohere.com", "together.ai", "groq.com",
                "replicate.com", "stability.ai", "runwayml.com", "lumalabs.ai", "pika.art",
                "elevenlabs.io", "suno.com", "udio.com", "ideogram.ai", "leonardo.ai",
                "civitai.com", "heygen.com", "synthesia.io", "descript.com",
                "cursor.com", "codeium.com", "tabnine.com", "phind.com", "poe.com", "character.ai",
            ),
        ),
        Section(
            "Соцсети",
            listOf(
                "instagram.com", "cdninstagram.com", "facebook.com", "fb.com", "fbcdn.net",
                "messenger.com", "threads.net", "twitter.com", "x.com", "twimg.com", "t.co",
                "linkedin.com", "licdn.com", "pinterest.com", "pinimg.com",
                "reddit.com", "redditstatic.com", "redd.it", "tumblr.com", "snapchat.com",
                "bsky.app", "mastodon.social", "quora.com", "medium.com",
            ),
        ),
        Section(
            "Мессенджеры",
            listOf(
                "discord.com", "discordapp.com", "discordapp.net", "discord.gg", "discordcdn.com",
                "signal.org", "signal.art", "viber.com", "skype.com",
                "slack.com", "slack-edge.com", "whatsapp.com", "whatsapp.net",
                "line.me", "element.io", "matrix.org", "wire.com", "threema.ch",
            ),
        ),
        Section(
            "Видео и музыка",
            listOf(
                "youtube.com", "youtu.be", "ytimg.com", "googlevideo.com", "ggpht.com",
                "netflix.com", "nflxvideo.net", "nflximg.net", "nflxext.com",
                "twitch.tv", "ttvnw.net", "jtvnw.net", "vimeo.com", "vimeocdn.com",
                "spotify.com", "scdn.co", "spotifycdn.com", "soundcloud.com", "sndcdn.com",
                "deezer.com", "tidal.com", "music.apple.com", "hulu.com", "disneyplus.com",
                "max.com", "primevideo.com", "crunchyroll.com", "dailymotion.com",
                "bandcamp.com", "last.fm", "mixcloud.com",
            ),
        ),
        Section(
            "Работа и дизайн",
            listOf(
                "canva.com", "figma.com", "miro.com", "notion.so", "notion.site",
                "atlassian.com", "atlassian.net", "trello.com", "asana.com", "monday.com",
                "clickup.com", "airtable.com", "zapier.com", "make.com", "loom.com",
                "calendly.com", "dropbox.com", "box.com", "wetransfer.com",
                "adobe.com", "adobelogin.com", "behance.net", "dribbble.com",
                "unsplash.com", "pexels.com", "freepik.com", "envato.com", "shutterstock.com",
                "framer.com", "webflow.com", "wix.com", "squarespace.com",
                "mailchimp.com", "hubspot.com", "intercom.com", "zendesk.com",
                "docusign.com", "grammarly.com", "deepl.com",
            ),
        ),
        Section(
            "Разработка",
            listOf(
                "github.com", "githubusercontent.com", "githubassets.com", "github.io",
                "gitlab.com", "bitbucket.org", "npmjs.com", "docker.com", "docker.io",
                "pypi.org", "pythonhosted.org", "crates.io", "jetbrains.com",
                "visualstudio.com", "vscode.dev", "stackoverflow.com", "stackexchange.com",
                "vercel.com", "netlify.com", "netlify.app", "cloudflare.com",
                "digitalocean.com", "heroku.com", "railway.app", "render.com",
                "supabase.com", "firebase.google.com", "aws.amazon.com", "cloud.google.com",
            ),
        ),
        Section(
            "Покупки и платежи",
            listOf(
                "amazon.com", "amazon.de", "amazon.co.uk", "media-amazon.com",
                "ebay.com", "etsy.com", "shein.com", "asos.com", "farfetch.com",
                "paypal.com", "paypalobjects.com", "stripe.com", "wise.com",
                "revolut.com", "payoneer.com", "skrill.com",
            ),
        ),
        Section(
            "Путешествия",
            listOf(
                "booking.com", "airbnb.com", "expedia.com", "skyscanner.net",
                "kayak.com", "tripadvisor.com", "agoda.com", "hotels.com", "uber.com",
            ),
        ),
        Section(
            "Игры",
            listOf(
                "steampowered.com", "steamcommunity.com", "steamstatic.com",
                "epicgames.com", "ea.com", "ubisoft.com", "battle.net", "blizzard.com",
                "playstation.com", "xbox.com", "nintendo.com", "roblox.com",
                "riotgames.com", "leagueoflegends.com", "gog.com", "itch.io",
            ),
        ),
        Section(
            "Новости и знания",
            listOf(
                "bbc.com", "bbc.co.uk", "cnn.com", "nytimes.com", "theguardian.com",
                "reuters.com", "bloomberg.com", "ft.com", "wsj.com", "economist.com",
                "dw.com", "archive.org",
            ),
        ),
        Section(
            "Обучение",
            listOf(
                "coursera.org", "udemy.com", "edx.org", "khanacademy.org",
                "duolingo.com", "skillshare.com", "pluralsight.com", "datacamp.com",
            ),
        ),
    )

    /** Все домены одним списком — в таком виде они уходят в маршрутизацию. */
    val domains: List<String> = sections.flatMap { it.domains }.distinct()

    val count: Int get() = domains.size

    /** Короткое описание для интерфейса: первые разделы через запятую. */
    val summary: String
        get() = sections.take(5).joinToString(", ") { it.title.lowercase() } + " и другое"


    // ——— Программы ———

    /**
     * Приложения, которым нужен зарубежный адрес.
     *
     * Список нужен для режима «только выбранные программы»: там Android требует
     * перечислить программы поимённо, и человек не должен отмечать их вручную.
     * Сюда собрано то, что стоит на телефонах чаще всего — по статистике
     * установок в Google Play и Galaxy Store.
     *
     * Имена пакетов, которых на телефоне нет, просто пропускаются.
     */
    data class AppSection(val title: String, val packages: List<String>)

    val appSections: List<AppSection> = listOf(
        AppSection(
            "Нейросети",
            listOf(
                "com.openai.chatgpt", "com.anthropic.claude", "ai.perplexity.app.android",
                "com.google.android.apps.bard", "com.microsoft.copilot", "ai.x.grok",
                "com.deepseek.chat", "ai.character.app", "com.midjourney.android",
                "io.elevenlabs.app", "com.leonardo.ai", "com.quora.poe",
            ),
        ),
        AppSection(
            "Соцсети",
            listOf(
                "com.instagram.android", "com.instagram.barcelona", "com.facebook.katana",
                "com.facebook.lite", "com.twitter.android", "com.linkedin.android",
                "com.pinterest", "com.reddit.frontpage", "com.snapchat.android",
                "com.zhiliaoapp.musically", "com.ss.android.ugc.trill", "com.tumblr",
                "xyz.blueskyweb.app", "com.medium.reader", "com.quora.android",
            ),
        ),
        AppSection(
            "Мессенджеры",
            listOf(
                "com.whatsapp", "com.whatsapp.w4b", "com.facebook.orca",
                "org.thoughtcrime.securesms", "com.discord", "com.viber.voip",
                "com.skype.raider", "com.microsoft.teams", "com.Slack",
                "us.zoom.videomeetings", "com.google.android.apps.tachyon",
                "com.google.android.apps.meetings", "com.signal.android",
            ),
        ),
        AppSection(
            "Видео и музыка",
            listOf(
                "com.google.android.youtube", "com.google.android.apps.youtube.music",
                "com.netflix.mediaclient", "com.spotify.music", "com.disney.disneyplus",
                "tv.twitch.android.app", "com.amazon.avod.thirdpartyclient", "com.wbd.stream",
                "com.soundcloud.android", "com.vimeo.android.videoapp", "deezer.android.app",
                "com.apple.android.music", "com.bandcamp.android",
            ),
        ),
        AppSection(
            "Работа и дизайн",
            listOf(
                "com.canva.editor", "com.figma.mirror", "com.notion.id", "com.miro.android",
                "com.adobe.lrmobile", "com.adobe.psmobile", "com.adobe.reader",
                "com.trello", "com.atlassian.android.jira.core", "com.asana.app",
                "com.dropbox.android", "com.microsoft.office.outlook", "com.upwork.android.apps.main",
                "com.fiverr.fiverr", "com.github.android", "com.stackexchange.marvin",
            ),
        ),
        AppSection(
            "Браузеры",
            listOf(
                "com.android.chrome", "com.sec.android.app.sbrowser", "org.mozilla.firefox",
                "com.opera.browser", "com.brave.browser", "com.microsoft.emmx",
                "com.duckduckgo.mobile.android", "org.torproject.torbrowser",
            ),
        ),
        AppSection(
            "Покупки и платежи",
            listOf(
                "com.amazon.mShop.android.shopping", "com.paypal.android.p2pmobile",
                "com.ebay.mobile", "com.etsy.android", "com.revolut.revolut",
                "com.wise.android", "com.binance.dev", "com.coinbase.android",
            ),
        ),
        AppSection(
            "Путешествия",
            listOf(
                "com.booking", "com.airbnb.android", "com.expedia.bookings",
                "net.skyscanner.android.main", "com.tripadvisor.tripadvisor",
                "com.ubercab", "com.kayak.android",
            ),
        ),
        AppSection(
            "Игры",
            listOf(
                "com.valvesoftware.android.steam.community", "com.epicgames.portal",
                "com.roblox.client", "com.blizzard.messenger", "com.playstation.remoteplay",
                "com.microsoft.xcloud", "com.nintendo.znca", "com.ea.gp.fifamobile",
            ),
        ),
        AppSection(
            "Новости и обучение",
            listOf(
                "bbc.mobile.news.ww", "com.cnn.mobile.android.phone", "com.nytimes.android",
                "com.guardian", "com.bloomberg.android.plus", "org.coursera.android",
                "com.udemy.android", "org.edx.mobile", "org.khanacademy.android", "com.duolingo",
            ),
        ),
    )

    /** Все программы одним списком. */
    val packages: List<String> = appSections.flatMap { it.packages }.distinct()

    val packageCount: Int get() = packages.size

    fun rules(): List<RoutingRule> = domains.map { domain ->
        RoutingRule(kind = RuleKind.DOMAIN, value = domain, note = "Обход блокировок")
    }
}
