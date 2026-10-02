package kz.qpvpn.model

/**
 * Сервисы, ради которых включают VPN.
 *
 * Через VPN идёт только то, что здесь перечислено: мессенджеры, видео
 * и сервисы искусственного интеллекта. Всё остальное — напрямую:
 * российские сайты, банки, маркетплейсы, МАХ, госуслуги, рабочая почта.
 * Так задумано: заворачивать в туннель то, что и без него работает,
 * значит замедлять его и ломать сервисы, которые VPN не любят.
 *
 * Список обязан совпадать с версией для Mac один в один — иначе на одном
 * устройстве сервис работает, а на другом нет, и разобраться в этом
 * невозможно. Сверяется проверками на обеих платформах.
 *
 * Адреса подобраны по одному правилу: в список попадают только сети,
 * принадлежащие самим сервисам. Сети посредников — Cloudflare, Google
 * Cloud — куда более широкие: на них стоят десятки тысяч чужих сайтов,
 * в том числе российских, и заворачивать их в туннель нельзя. Это
 * проверено на живых адресах. Поэтому сервисы, живущие на Cloudflare
 * (ChatGPT и почти все ИИ), ходят через VPN по точным адресам из DNS.
 */
object VpnServices {

    data class Service(
        /** Как называется на экране. */
        val title: String,
        /** Собственные сети сервиса — их можно смело вести в туннель. */
        val networks: List<String>,
        /** Имена, чьи адреса спрашиваем у DNS. */
        val domains: List<String>,
    )

    /**
     * Собственные сети Google: поиск, YouTube, раздача видео, Gemini.
     *
     * Сетей Google Cloud здесь нарочно нет. Google Cloud сдаётся
     * в аренду, и на нём стоят чужие сайты, включая российские.
     */
    val GOOGLE = listOf(
        "64.233.160.0/19", "66.102.0.0/20", "66.249.64.0/19", "72.14.192.0/18",
        "74.125.0.0/16", "108.177.0.0/17", "142.250.0.0/15", "142.251.0.0/16",
        "172.217.0.0/16", "172.253.0.0/16", "173.194.0.0/16", "192.178.0.0/15",
        "207.223.160.0/20", "209.85.128.0/17", "216.58.192.0/19", "216.239.32.0/19",
        "208.65.152.0/22", "208.68.108.0/22",
    )

    /** Сети Meta: WhatsApp и Instagram. */
    val META = listOf(
        "31.13.24.0/21", "31.13.64.0/18", "45.64.40.0/22", "57.144.0.0/14",
        "66.220.144.0/20", "69.63.176.0/20", "69.171.224.0/19", "74.119.76.0/22",
        "103.4.96.0/22", "129.134.0.0/16", "157.240.0.0/16", "173.252.64.0/18",
        "179.60.192.0/22", "185.60.216.0/22", "204.15.20.0/22",
    )

    /** Сети Telegram. Небольшие и целиком его собственные. */
    val TELEGRAM = listOf(
        "91.108.4.0/22", "91.108.8.0/22", "91.108.12.0/22", "91.108.16.0/22",
        "91.108.20.0/22", "91.108.56.0/22", "149.154.160.0/20", "185.76.151.0/24",
    )

    /**
     * Сети Cloudflare: на них стоят ИИ-сервисы — и чужие сайты тоже.
     *
     * В туннель НЕ уходят: слишком широкие. Нужны для другого — чтобы
     * проверить, настоящий ли адрес назвал DNS.
     */
    val CLOUDFLARE = listOf(
        "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
        "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
        "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
        "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    )

    val services: List<Service> = listOf(

        // ── Мессенджеры ──────────────────────────────────────────────

        // WhatsApp и Instagram живут в сетях Meta. Фото и видео отдаются
        // с отдельных адресов, поэтому имена для них перечислены особо:
        // без них сообщения ходят, а медиа не грузится.
        Service(
            "WhatsApp", META,
            listOf(
                "whatsapp.com", "www.whatsapp.com", "web.whatsapp.com",
                "whatsapp.net", "static.whatsapp.net", "mmg.whatsapp.net",
                "media.whatsapp.net", "g.whatsapp.net",
            ),
        ),
        Service(
            "Instagram", META,
            listOf(
                "instagram.com", "www.instagram.com", "i.instagram.com",
                "graph.instagram.com", "scontent.cdninstagram.com",
                "cdninstagram.com", "static.cdninstagram.com",
            ),
        ),
        // У Telegram свои сети, и они небольшие: ведём их целиком.
        Service(
            "Telegram", TELEGRAM,
            listOf(
                "telegram.org", "web.telegram.org", "core.telegram.org",
                "api.telegram.org", "t.me", "telegram.me", "telesco.pe",
            ),
        ),

        // ── Видео ────────────────────────────────────────────────────

        // YouTube отдаёт видео с серверов, имена которых каждый раз новые
        // (rr3---sn-… .googlevideo.com) — перечислить их нельзя. Зато все
        // они стоят в собственных сетях Google.
        Service(
            "YouTube", GOOGLE,
            listOf(
                "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
                "i.ytimg.com", "s.ytimg.com", "yt3.ggpht.com",
                "youtubei.googleapis.com", "redirector.googlevideo.com",
                "manifest.googlevideo.com",
            ),
        ),

        // ── Искусственный интеллект ──────────────────────────────────

        // Собственных сетей у ChatGPT нет: и сайт, и обращения программ
        // идут через Cloudflare, где рядом стоят чужие сайты.
        Service(
            "ChatGPT", emptyList(),
            listOf(
                "chatgpt.com", "www.chatgpt.com", "ab.chatgpt.com",
                "sora.chatgpt.com", "openai.com", "www.openai.com",
                "api.openai.com", "auth.openai.com", "auth0.openai.com",
                "chat.openai.com", "platform.openai.com",
                "cdn.oaistatic.com", "files.oaiusercontent.com",
                "videos.openai.com",
            ),
        ),
        // Anthropic держит свою сеть, чужого на ней нет.
        Service(
            "Claude", listOf("160.79.104.0/23"),
            listOf(
                "claude.ai", "www.claude.ai", "claude.com", "www.claude.com",
                "anthropic.com", "www.anthropic.com", "api.anthropic.com",
                "console.anthropic.com",
            ),
        ),
        // Gemini — в сетях Google, там же, где YouTube.
        Service(
            "Gemini", GOOGLE,
            listOf(
                "gemini.google.com", "aistudio.google.com",
                "generativelanguage.googleapis.com", "notebooklm.google.com",
                "labs.google", "deepmind.google",
            ),
        ),
        Service("Perplexity", emptyList(),
            listOf("perplexity.ai", "www.perplexity.ai", "pplx.ai")),
        Service("Grok", emptyList(),
            listOf("grok.com", "www.grok.com", "x.ai", "api.x.ai")),
        Service("Copilot", emptyList(),
            listOf("copilot.microsoft.com", "github.com", "api.github.com",
                   "copilot-proxy.githubusercontent.com")),
        Service("DeepSeek", emptyList(),
            listOf("deepseek.com", "www.deepseek.com", "chat.deepseek.com",
                   "api.deepseek.com")),
        Service("Mistral", emptyList(),
            listOf("mistral.ai", "chat.mistral.ai", "api.mistral.ai")),
        Service("Midjourney", emptyList(),
            listOf("midjourney.com", "www.midjourney.com", "cdn.midjourney.com")),
        Service("Suno", emptyList(),
            listOf("suno.com", "www.suno.com", "studio.suno.com")),
        Service("Hugging Face", emptyList(),
            listOf("huggingface.co", "cdn-lfs.huggingface.co")),
    )

    /** Названия для показа на экране. */
    val titles: List<String> get() = services.map { it.title }

    /**
     * Правила маршрутизации для зашитого списка.
     *
     * Сети — как есть, имена — через DNS: приложение спрашивает адреса
     * само и обновляет их, пока туннель поднят. Имена сервисов, живущих
     * на Cloudflare, иначе в туннель не провести.
     */
    fun rules(): List<RoutingRule> = buildList {
        for (service in services) {
            for (network in service.networks) {
                add(RoutingRule(id = "сеть:$network", kind = RuleKind.CIDR,
                                value = network, note = service.title))
            }
            for (domain in service.domains) {
                add(RoutingRule(id = "имя:$domain", kind = RuleKind.DOMAIN,
                                value = domain, note = service.title))
            }
        }
    }

}
