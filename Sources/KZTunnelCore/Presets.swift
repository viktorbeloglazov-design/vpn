import Foundation

/// Готовые наборы правил, чтобы не набивать списки руками.
public struct RulePreset: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// Для какого режима набор имеет смысл.
    public let mode: TunnelMode
    public let values: [PresetValue]

    public struct PresetValue: Sendable {
        public let kind: RuleKind
        public let value: String

        public init(_ kind: RuleKind, _ value: String) {
            self.kind = kind
            self.value = value
        }
    }

    public var rules: [RoutingRule] {
        values.map { RoutingRule(kind: $0.kind, value: $0.value, enabled: true, note: title) }
    }
}

public enum Presets {

    public static let all: [RulePreset] = [
        RulePreset(
            id: "kz-services",
            title: "Сервисы Казахстана",
            subtitle: "Банки, госуслуги, доски объявлений и связь KZ — направить в туннель.",
            mode: .include,
            values: [
                .init(.domain, "kaspi.kz"),
                .init(.domain, "halykbank.kz"),
                .init(.domain, "homebank.kz"),
                .init(.domain, "egov.kz"),
                .init(.domain, "gov.kz"),
                .init(.domain, "salyk.kz"),
                .init(.domain, "enbek.kz"),
                .init(.domain, "olx.kz"),
                .init(.domain, "kolesa.kz"),
                .init(.domain, "krisha.kz"),
                .init(.domain, "market.kz"),
                .init(.domain, "wildberries.kz"),
                .init(.domain, "ozon.kz"),
                .init(.domain, "beeline.kz"),
                .init(.domain, "kcell.kz"),
                .init(.domain, "tele2.kz"),
                .init(.domain, "2gis.kz"),
            ]
        ),
        RulePreset(
            id: "ru-banking",
            title: "Банки и госуслуги РФ",
            subtitle: "Оставить напрямую: с зарубежного IP такие сайты часто блокируют вход.",
            mode: .exclude,
            values: [
                .init(.domain, "sberbank.ru"),
                .init(.domain, "online.sberbank.ru"),
                .init(.domain, "alfabank.ru"),
                .init(.domain, "tbank.ru"),
                .init(.domain, "tinkoff.ru"),
                .init(.domain, "vtb.ru"),
                .init(.domain, "gosuslugi.ru"),
                .init(.domain, "nalog.gov.ru"),
                .init(.domain, "nalog.ru"),
                .init(.domain, "cbr.ru"),
            ]
        ),
        RulePreset(
            id: "ru-marketplaces",
            title: "Маркетплейсы РФ",
            subtitle: "Личные кабинеты продавца: Wildberries, Ozon, Яндекс Маркет — мимо VPN.",
            mode: .exclude,
            values: [
                .init(.domain, "wildberries.ru"),
                .init(.domain, "seller.wildberries.ru"),
                .init(.domain, "ozon.ru"),
                .init(.domain, "seller.ozon.ru"),
                .init(.domain, "market.yandex.ru"),
                .init(.domain, "partner.market.yandex.ru"),
                .init(.domain, "yandex.ru"),
                .init(.domain, "megamarket.ru"),
            ]
        ),
        RulePreset(
            id: "cn-suppliers",
            title: "Китайские поставщики",
            subtitle: "1688, Alibaba, Taobao, WeChat — оставить на прямом канале.",
            mode: .exclude,
            values: [
                .init(.domain, "1688.com"),
                .init(.domain, "alibaba.com"),
                .init(.domain, "taobao.com"),
                .init(.domain, "tmall.com"),
                .init(.domain, "aliexpress.com"),
                .init(.domain, "wechat.com"),
                .init(.domain, "qq.com"),
            ]
        ),
        RulePreset(
            id: "local-net",
            title: "Локальная сеть и принтеры",
            subtitle: "Частные подсети — всегда напрямую (обычно и так работает, но с этим надёжнее).",
            mode: .exclude,
            values: [
                .init(.cidr, "10.0.0.0/8"),
                .init(.cidr, "172.16.0.0/12"),
                .init(.cidr, "192.168.0.0/16"),
                .init(.cidr, "169.254.0.0/16"),
            ]
        ),
        RulePreset(
            id: "video-calls",
            title: "Видеозвонки",
            subtitle: "Zoom, Teams, Meet — напрямую, чтобы не терять качество на лишнем плече.",
            mode: .exclude,
            values: [
                .init(.domain, "zoom.us"),
                .init(.domain, "teams.microsoft.com"),
                .init(.domain, "meet.google.com"),
                .init(.domain, "telegram.org"),
            ]
        ),
    ]

    public static func preset(id: String) -> RulePreset? {
        all.first { $0.id == id }
    }
}
