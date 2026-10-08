import Foundation

/// Сервисы, ради которых включают VPN.
///
/// Через VPN идёт только то, что здесь перечислено: мессенджеры, видео
/// и сервисы искусственного интеллекта. Всё остальное — напрямую:
/// российские сайты, банки, маркетплейсы, МАХ, госуслуги, рабочая почта,
/// 1С. Так задумано: заворачивать в туннель то, что и без него работает,
/// значит замедлять его и ломать сервисы, которые VPN не любят.
///
/// Адреса подобраны по одному правилу: в список попадают только сети,
/// принадлежащие самим сервисам. Сети посредников — Cloudflare, Google
/// Cloud — куда более широкие: на них стоят десятки тысяч чужих сайтов,
/// в том числе российских, и заворачивать их в туннель нельзя. Это
/// проверено: за Cloudflare стоят и rutracker, и множество российских
/// сайтов. Поэтому сервисы, живущие на Cloudflare (ChatGPT и почти все
/// ИИ), ходят через VPN по точным адресам, которые спрашиваются у DNS,
/// а не по чужим сетям.
public enum VpnServices {

    public struct Service: Sendable {
        /// Как называется в окне.
        public let title: String
        /// Собственные сети сервиса — их можно смело вести в туннель.
        public let networks: [String]
        /// Имена, чьи адреса спрашиваем у DNS.
        public let domains: [String]

        public init(title: String, networks: [String], domains: [String]) {
            self.title = title
            self.networks = networks
            self.domains = domains
        }
    }

    public static let services: [Service] = [

        // ── Мессенджеры ──────────────────────────────────────────────

        // WhatsApp и Instagram живут в сетях Meta. Фото и видео отдаются
        // с отдельных адресов (mmg, scontent), поэтому имена для них
        // перечислены особо: без них сообщения ходят, а медиа не грузится.
        Service(title: "WhatsApp", networks: meta,
                domains: ["whatsapp.com", "www.whatsapp.com", "web.whatsapp.com",
                          "whatsapp.net", "static.whatsapp.net", "mmg.whatsapp.net",
                          "media.whatsapp.net", "g.whatsapp.net"]),

        Service(title: "Instagram", networks: meta,
                domains: ["instagram.com", "www.instagram.com", "i.instagram.com",
                          "graph.instagram.com", "scontent.cdninstagram.com",
                          "cdninstagram.com", "static.cdninstagram.com"]),

        // У Telegram свои сети, и они небольшие: ведём их целиком.
        Service(title: "Telegram", networks: telegram,
                domains: ["telegram.org", "web.telegram.org", "core.telegram.org",
                          "api.telegram.org", "t.me", "telegram.me", "telesco.pe"]),

        // ── Видео ────────────────────────────────────────────────────

        // YouTube отдаёт видео с серверов, имена которых каждый раз новые
        // (rr3---sn-… .googlevideo.com) — перечислить их нельзя. Зато все
        // они стоят в собственных сетях Google.
        Service(title: "YouTube", networks: google,
                domains: ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
                          "i.ytimg.com", "s.ytimg.com", "yt3.ggpht.com",
                          "youtubei.googleapis.com", "redirector.googlevideo.com",
                          "manifest.googlevideo.com"]),

        // ── Искусственный интеллект ──────────────────────────────────

        // Собственных сетей у ChatGPT нет: и сайт, и обращения программ
        // идут через Cloudflare, где рядом стоят чужие сайты. Только
        // точные адреса из DNS.
        Service(title: "ChatGPT", networks: [],
                domains: ["chatgpt.com", "www.chatgpt.com", "ab.chatgpt.com",
                          "sora.chatgpt.com", "openai.com", "www.openai.com",
                          "api.openai.com", "auth.openai.com", "auth0.openai.com",
                          "chat.openai.com", "platform.openai.com",
                          "cdn.oaistatic.com", "files.oaiusercontent.com",
                          "videos.openai.com"]),

        // Anthropic держит свою сеть, чужого на ней нет.
        Service(title: "Claude", networks: ["160.79.104.0/23"],
                domains: ["claude.ai", "www.claude.ai", "claude.com", "www.claude.com",
                          "anthropic.com", "www.anthropic.com", "api.anthropic.com",
                          "console.anthropic.com"]),

        // Gemini — в сетях Google, там же, где YouTube.
        Service(title: "Gemini", networks: google,
                domains: ["gemini.google.com", "aistudio.google.com",
                          "generativelanguage.googleapis.com", "notebooklm.google.com",
                          "labs.google", "deepmind.google"]),

        // Остальные ИИ — все на Cloudflare, только по адресам из DNS.
        Service(title: "Perplexity", networks: [],
                domains: ["perplexity.ai", "www.perplexity.ai", "pplx.ai"]),

        Service(title: "Grok", networks: [],
                domains: ["grok.com", "www.grok.com", "x.ai", "api.x.ai"]),

        Service(title: "Copilot", networks: [],
                domains: ["copilot.microsoft.com", "github.com", "api.github.com",
                          "copilot-proxy.githubusercontent.com"]),

        Service(title: "DeepSeek", networks: [],
                domains: ["deepseek.com", "www.deepseek.com", "chat.deepseek.com",
                          "api.deepseek.com"]),

        Service(title: "Mistral", networks: [],
                domains: ["mistral.ai", "chat.mistral.ai", "api.mistral.ai"]),

        Service(title: "Midjourney", networks: [],
                domains: ["midjourney.com", "www.midjourney.com", "cdn.midjourney.com"]),

        Service(title: "Suno", networks: [],
                domains: ["suno.com", "www.suno.com", "studio.suno.com"]),

        Service(title: "Hugging Face", networks: [],
                domains: ["huggingface.co", "cdn-lfs.huggingface.co"]),
    ]

    /// Названия для показа в окне.
    public static var titles: [String] { services.map(\.title) }

    // MARK: - Мимо VPN внутри сетей Google

    /// Gmail — мимо VPN.
    ///
    /// Gmail стоит в тех же сетях Google, что YouTube и Gemini, а эти сети
    /// целиком уходят в туннель. Поэтому почта шла через Казахстан, хотя
    /// из России она открывается и так. Для её адресов служба кладёт
    /// точные маршруты мимо туннеля: точный маршрут для системы важнее
    /// широкой сети, и почта уходит напрямую, а YouTube остаётся в VPN.
    ///
    /// Вход в аккаунт (accounts.google.com) и общие картинки Google
    /// (gstatic) — общие с YouTube, они остаются в VPN: почте это
    /// не мешает.
    public static let directTitle = "Gmail"
    public static let directDomains = [
        "mail.google.com", "gmail.com", "www.gmail.com", "inbox.google.com",
        "imap.gmail.com", "smtp.gmail.com", "pop.gmail.com",
        "mail-attachment.googleusercontent.com", "mail.googleusercontent.com",
    ]

    /// Какие адреса Gmail пускать мимо VPN.
    ///
    /// Google раздаёт с одного адреса многие свои сервисы, и DNS может
    /// назвать для почты тот же адрес, что и для YouTube. Такой адрес
    /// напрямую не пускаем: иначе вместе с почтой мимо VPN ушёл бы
    /// YouTube. Почта на нём пойдёт через VPN — работать она будет.
    ///
    /// - gmailAddresses: что DNS ответил на имена Gmail.
    /// - tunnelRoutes: что уже идёт в туннель по именам и сетям сервисов.
    public static func directNets(gmailAddresses: [String], tunnelRoutes: Set<String>) -> [Ipv4Net] {
        var result: [Ipv4Net] = []
        for address in gmailAddresses where !address.contains(":") {
            guard let net = Cidr.parse(address + "/32"), Cidr.isPublicAddress(net) else { continue }
            if tunnelRoutes.contains(net.text) { continue }
            if !result.contains(net) { result.append(net) }
        }
        return result
    }

    /// Правила маршрутизации для зашитого списка.
    ///
    /// Сети — как есть, имена — через DNS: служба спрашивает адреса сама
    /// и обновляет их, пока туннель поднят. Имена сервисов, живущих на
    /// Cloudflare, иначе в туннель не провести.
    public static func rules() -> [RoutingRule] {
        var result: [RoutingRule] = []
        for service in services {
            for network in service.networks {
                result.append(RoutingRule(id: "сеть:\(network)",
                                          kind: .cidr,
                                          value: network,
                                          note: service.title))
            }
            for domain in service.domains {
                result.append(RoutingRule(id: "имя:\(domain)",
                                          kind: .domain,
                                          value: domain,
                                          note: service.title))
            }
        }
        return result
    }

    // MARK: - Сети владельцев

    /// Собственные сети Google: поиск, YouTube, раздача видео, Gemini.
    ///
    /// Сетей Google Cloud здесь нарочно нет. Google Cloud сдаётся
    /// в аренду, и на нём стоят чужие сайты, включая российские.
    static let google = [
        "64.233.160.0/19", "66.102.0.0/20", "66.249.64.0/19", "72.14.192.0/18",
        "74.125.0.0/16", "108.177.0.0/17", "142.250.0.0/15", "142.251.0.0/16",
        "172.217.0.0/16", "172.253.0.0/16", "173.194.0.0/16", "192.178.0.0/15",
        "207.223.160.0/20", "209.85.128.0/17", "216.58.192.0/19", "216.239.32.0/19",
        "208.65.152.0/22", "208.68.108.0/22",
    ]

    /// Сети Meta: WhatsApp и Instagram.
    static let meta = [
        "31.13.24.0/21", "31.13.64.0/18", "45.64.40.0/22", "57.144.0.0/14",
        "66.220.144.0/20", "69.63.176.0/20", "69.171.224.0/19", "74.119.76.0/22",
        "103.4.96.0/22", "129.134.0.0/16", "157.240.0.0/16", "173.252.64.0/18",
        "179.60.192.0/22", "185.60.216.0/22", "204.15.20.0/22",
    ]

    /// Сети Telegram. Небольшие и целиком его собственные.
    static let telegram = [
        "91.108.4.0/22", "91.108.8.0/22", "91.108.12.0/22", "91.108.16.0/22",
        "91.108.20.0/22", "91.108.56.0/22", "149.154.160.0/20", "185.76.151.0/24",
    ]

    /// Сети Cloudflare: на них стоят ИИ-сервисы — и чужие сайты тоже.
    ///
    /// В туннель НЕ уходят: слишком широкие. Нужны для другого — чтобы
    /// проверить, настоящий ли адрес назвал DNS.
    static let cloudflare = [
        "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
        "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
        "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
        "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    ]

    private static let ownerNets: [Ipv4Net] =
        (google + meta + telegram + cloudflare + ["160.79.104.0/23"])
        .compactMap(Cidr.parse)

    /// Похож ли адрес на настоящий адрес сервиса.
    ///
    /// Нужно перед тем, как проложить маршрут к ответу DNS. На
    /// заблокированное имя провайдер нередко отвечает адресом своей
    /// заглушки — адрес живой, публичный, российский. Проложить к нему
    /// маршрут значит увести в туннель чужой трафик.
    public static func isServiceAddress(_ net: Ipv4Net) -> Bool {
        guard Cidr.isPublicAddress(net) else { return false }
        return ownerNets.contains { owner in
            Int64(net.start) >= Int64(owner.start) && Int64(net.start) <= owner.endInclusive
        }
    }
}
