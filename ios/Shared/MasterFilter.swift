// Создано скриптом из android/app/src/main/java/kz/qpvpn/model/MasterFilter.kt —
// списки на всех платформах одни и те же. Править нужно тот файл, а не этот.

import Foundation

/// Главный фильтр: всё, что не открывается с российского адреса.
enum MasterFilter {

    struct Section {
        let title: String
        let domains: [String]
    }

    static let sections: [Section] = [
        Section(title: "Нейросети", domains: [
            "openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "sora.com",
            "anthropic.com", "claude.ai", "claudeusercontent.com", "gemini.google.com", "aistudio.google.com",
            "bard.google.com", "deepmind.google", "perplexity.ai", "midjourney.com", "huggingface.co",
            "copilot.microsoft.com", "x.ai", "grok.com", "mistral.ai", "cohere.com", "together.ai",
            "groq.com", "replicate.com", "stability.ai", "runwayml.com", "lumalabs.ai", "pika.art",
            "elevenlabs.io", "suno.com", "udio.com", "ideogram.ai", "leonardo.ai", "civitai.com",
            "heygen.com", "synthesia.io", "descript.com", "cursor.com", "codeium.com", "tabnine.com",
            "phind.com", "poe.com", "character.ai",
        ]),
        Section(title: "Соцсети", domains: [
            "instagram.com", "cdninstagram.com", "facebook.com", "fb.com", "fbcdn.net", "messenger.com",
            "threads.net", "twitter.com", "x.com", "twimg.com", "t.co", "linkedin.com", "licdn.com",
            "pinterest.com", "pinimg.com", "reddit.com", "redditstatic.com", "redd.it", "tumblr.com",
            "snapchat.com", "bsky.app", "mastodon.social", "quora.com", "medium.com",
        ]),
        Section(title: "Мессенджеры", domains: [
            "discord.com", "discordapp.com", "discordapp.net", "discord.gg", "discordcdn.com",
            "signal.org", "signal.art", "viber.com", "skype.com", "slack.com", "slack-edge.com",
            "whatsapp.com", "whatsapp.net", "line.me", "element.io", "matrix.org", "wire.com",
            "threema.ch",
        ]),
        Section(title: "Видео и музыка", domains: [
            "youtube.com", "youtu.be", "ytimg.com", "googlevideo.com", "ggpht.com", "netflix.com",
            "nflxvideo.net", "nflximg.net", "nflxext.com", "twitch.tv", "ttvnw.net", "jtvnw.net",
            "vimeo.com", "vimeocdn.com", "spotify.com", "scdn.co", "spotifycdn.com", "soundcloud.com",
            "sndcdn.com", "deezer.com", "tidal.com", "music.apple.com", "hulu.com", "disneyplus.com",
            "max.com", "primevideo.com", "crunchyroll.com", "dailymotion.com", "bandcamp.com",
            "last.fm", "mixcloud.com",
        ]),
        Section(title: "Работа и дизайн", domains: [
            "canva.com", "figma.com", "miro.com", "notion.so", "notion.site", "atlassian.com",
            "atlassian.net", "trello.com", "asana.com", "monday.com", "clickup.com", "airtable.com",
            "zapier.com", "make.com", "loom.com", "calendly.com", "dropbox.com", "box.com",
            "wetransfer.com", "adobe.com", "adobelogin.com", "behance.net", "dribbble.com",
            "unsplash.com", "pexels.com", "freepik.com", "envato.com", "shutterstock.com", "framer.com",
            "webflow.com", "wix.com", "squarespace.com", "mailchimp.com", "hubspot.com", "intercom.com",
            "zendesk.com", "docusign.com", "grammarly.com", "deepl.com",
        ]),
        Section(title: "Разработка", domains: [
            "github.com", "githubusercontent.com", "githubassets.com", "github.io", "gitlab.com",
            "bitbucket.org", "npmjs.com", "docker.com", "docker.io", "pypi.org", "pythonhosted.org",
            "crates.io", "jetbrains.com", "visualstudio.com", "vscode.dev", "stackoverflow.com",
            "stackexchange.com", "vercel.com", "netlify.com", "netlify.app", "cloudflare.com",
            "digitalocean.com", "heroku.com", "railway.app", "render.com", "supabase.com", "firebase.google.com",
            "aws.amazon.com", "cloud.google.com",
        ]),
        Section(title: "Покупки и платежи", domains: [
            "amazon.com", "amazon.de", "amazon.co.uk", "media-amazon.com", "ebay.com", "etsy.com",
            "shein.com", "asos.com", "farfetch.com", "paypal.com", "paypalobjects.com", "stripe.com",
            "wise.com", "revolut.com", "payoneer.com", "skrill.com",
        ]),
        Section(title: "Путешествия", domains: [
            "booking.com", "airbnb.com", "expedia.com", "skyscanner.net", "kayak.com", "tripadvisor.com",
            "agoda.com", "hotels.com", "uber.com",
        ]),
        Section(title: "Игры", domains: [
            "steampowered.com", "steamcommunity.com", "steamstatic.com", "epicgames.com", "ea.com",
            "ubisoft.com", "battle.net", "blizzard.com", "playstation.com", "xbox.com", "nintendo.com",
            "roblox.com", "riotgames.com", "leagueoflegends.com", "gog.com", "itch.io",
        ]),
        Section(title: "Новости и знания", domains: [
            "bbc.com", "bbc.co.uk", "cnn.com", "nytimes.com", "theguardian.com", "reuters.com",
            "bloomberg.com", "ft.com", "wsj.com", "economist.com", "dw.com", "archive.org",
        ]),
        Section(title: "Обучение", domains: [
            "coursera.org", "udemy.com", "edx.org", "khanacademy.org", "duolingo.com", "skillshare.com",
            "pluralsight.com", "datacamp.com",
        ]),
    ]

    /// Все домены одним списком — в таком виде они уходят в маршрутизацию.
    static let domains: [String] = {
        var seen = Set<String>()
        return sections.flatMap(\.domains).filter { seen.insert($0).inserted }
    }()

    static var count: Int { domains.count }
}
