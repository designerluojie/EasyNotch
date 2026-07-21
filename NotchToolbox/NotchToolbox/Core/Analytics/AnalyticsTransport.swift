import Foundation

nonisolated protocol AnalyticsTransport: Sendable {
    /// 发送一条事件。实现必须吞掉所有错误——埋点绝不允许影响主体验。
    /// 返回是否确认送达：按天去重的事件在失败时会撤销当天标记以便稍后重试
    /// （合盖唤醒后 Wi-Fi 未连上是刘海工具最典型的使用时刻，首次 app_active
    /// 若丢失且不重试，当天日活会系统性低估）。
    func send(name: String, properties: [String: String]) async -> Bool
}

/// 未配置 Umami 时使用：吞掉一切事件，不产生任何网络请求。
/// 报告"成功"：若报失败，去重标记会被撤销，未配置的构建将反复空转重试。
nonisolated struct DisabledAnalyticsTransport: AnalyticsTransport {
    func send(name: String, properties: [String: String]) async -> Bool { true }
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

    /// Umami Cloud 对非浏览器形态的 User-Agent 做机器人拦截——返回 200 但静默丢弃数据
    /// （响应体为 {"beep":"boop"}，而非正常的 {"cache":"..."}）。实测 "EasyNotch (macOS)"
    /// 会被拦掉，必须是浏览器形态才被接收。这里用标准 macOS Chrome UA 打底，
    /// 尾部保留 EasyNotch/版本 以便在后台仍能识别真实来源，而非纯粹伪装成浏览器。
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 EasyNotch/\(version)"
    }

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
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = data
        request.timeoutInterval = 10
        return request
    }

    func send(name: String, properties: [String: String]) async -> Bool {
        guard let request = Self.makeRequest(
            configuration: configuration,
            name: name,
            properties: properties
        ) else {
            // 构造请求失败属于编程错误而非网络问题，重试也不会变好——按成功处理，
            // 避免去重标记被反复撤销
            return true
        }

        // 失败静默：不落盘、不向用户暴露；只把结果告知调用方用于去重撤销
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return false
        }

        // 机器人拦截也是 200，只有响应体不同——仅看状态码会把被丢弃的数据误判为送达，
        // 进而错误地保留去重标记，当天不再重试。
        return Self.isAcceptedResponseBody(data)
    }

    /// Umami 接收成功返回 `{"cache":"<token>"}`；被机器人拦截返回 `{"beep":"boop"}`。
    static func isAcceptedResponseBody(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 响应体解析不了时不武断判负：状态码已是 2xx，按送达处理，避免无谓重试
            return true
        }
        return json["beep"] == nil
    }
}
