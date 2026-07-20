import Foundation

nonisolated protocol AnalyticsTransport: Sendable {
    /// 发送一条事件。实现必须吞掉所有错误——埋点绝不允许影响主体验。
    func send(name: String, properties: [String: String]) async
}

/// 未配置 Umami 时使用：吞掉一切事件，不产生任何网络请求。
nonisolated struct DisabledAnalyticsTransport: AnalyticsTransport {
    func send(name: String, properties: [String: String]) async {}
}

nonisolated struct UmamiConfiguration: Equatable, Sendable {
    let endpoint: URL
    let websiteID: String

    init(endpoint: URL, websiteID: String) {
        self.endpoint = endpoint
        self.websiteID = websiteID
    }

    /// 从字符串构造；任一项为空或非法则返回 nil，代表「未配置」，上报整体禁用。
    init?(endpointString: String, websiteID: String) {
        let trimmedID = websiteID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = endpointString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedID.isEmpty == false,
              trimmedEndpoint.isEmpty == false,
              let url = URL(string: trimmedEndpoint),
              url.scheme != nil,
              url.host != nil else {
            return nil
        }
        self.endpoint = url
        self.websiteID = trimmedID
    }
}

nonisolated struct UmamiAnalyticsTransport: AnalyticsTransport {
    private let configuration: UmamiConfiguration
    private let session: URLSession

    init(configuration: UmamiConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Umami 用 hostname 归类来源。原生 App 没有域名，用固定标识占位。
    static let hostname = "app.easynotch"

    static func makeRequest(
        configuration: UmamiConfiguration,
        name: String,
        properties: [String: String]
    ) -> URLRequest? {
        let payload: [String: Any] = [
            "website": configuration.websiteID,
            "hostname": hostname,
            "name": name,
            "data": properties
        ]
        let body: [String: Any] = ["type": "event", "payload": payload]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Umami 对缺少 User-Agent 的请求直接返回 403
        request.setValue("EasyNotch (macOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = data
        request.timeoutInterval = 10
        return request
    }

    func send(name: String, properties: [String: String]) async {
        guard let request = Self.makeRequest(
            configuration: configuration,
            name: name,
            properties: properties
        ) else {
            return
        }

        // 失败静默丢弃：不重试、不落盘、不向用户暴露
        _ = try? await session.data(for: request)
    }
}
