import Foundation
import Testing
@testable import NotchToolbox

struct AnalyticsTransportTests {
    @Test func umamiRequestCarriesWebsiteIdEventNameAndProperties() throws {
        let config = UmamiConfiguration(
            endpoint: URL(string: "https://cloud.umami.is/api/send")!,
            websiteID: "abc-123"
        )

        let request = try #require(UmamiAnalyticsTransport.makeRequest(
            configuration: config,
            name: "module_opened",
            properties: ["module": "music"]
        ))

        #expect(request.url?.absoluteString == "https://cloud.umami.is/api/send")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        // Umami Cloud 会对非浏览器形态的 User-Agent 做机器人拦截：返回 200 但丢弃数据
        // （响应体是 {"beep":"boop"} 而非正常的 {"cache":"..."}）。实测 "EasyNotch (macOS)"
        // 被拦，标准浏览器 UA 才被接收。这里锁住浏览器形态 + 保留 EasyNotch 来源标识。
        let userAgent = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(userAgent.hasPrefix("Mozilla/5.0"))
        #expect(userAgent.contains("Macintosh"))
        #expect(userAgent.contains("EasyNotch/"))

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["type"] as? String == "event")

        let payload = try #require(json["payload"] as? [String: Any])
        #expect(payload["website"] as? String == "abc-123")
        #expect(payload["name"] as? String == "module_opened")
        #expect(payload["hostname"] as? String != nil)

        let data = try #require(payload["data"] as? [String: Any])
        #expect(data["module"] as? String == "music")
    }

    // 配置留空即整体禁用，本地开发与测试不触网
    @Test func configurationIsNilWhenWebsiteIdIsBlank() {
        #expect(UmamiConfiguration(endpointString: "https://cloud.umami.is/api/send", websiteID: "") == nil)
        #expect(UmamiConfiguration(endpointString: "https://cloud.umami.is/api/send", websiteID: "   ") == nil)
        #expect(UmamiConfiguration(endpointString: "", websiteID: "abc-123") == nil)
        #expect(UmamiConfiguration(endpointString: "not a url", websiteID: "abc-123") == nil)
    }

    @Test func validConfigurationIsBuiltFromStrings() throws {
        let config = try #require(UmamiConfiguration(
            endpointString: "https://cloud.umami.is/api/send",
            websiteID: "abc-123"
        ))

        #expect(config.websiteID == "abc-123")
        #expect(config.endpoint.absoluteString == "https://cloud.umami.is/api/send")
    }

    // 机器人拦截与正常接收都是 HTTP 200，只有响应体不同。仅看状态码会把被丢弃的
    // 数据误判为送达，从而保留去重标记、当天不再重试。
    @Test func botBlockedResponseBodyIsNotTreatedAsDelivered() {
        let blocked = Data(#"{"beep":"boop"}"#.utf8)
        let accepted = Data(#"{"cache":"eyJhbGciOiJIUzI1NiJ9.payload.sig"}"#.utf8)

        #expect(UmamiAnalyticsTransport.isAcceptedResponseBody(blocked) == false)
        #expect(UmamiAnalyticsTransport.isAcceptedResponseBody(accepted))
    }

    // 解析不了的响应体不武断判负：状态码已是 2xx，按送达处理，避免无谓重试
    @Test func unparseableResponseBodyIsTreatedAsDelivered() {
        #expect(UmamiAnalyticsTransport.isAcceptedResponseBody(Data("ok".utf8)))
    }

    // 未配置 Umami 时用的空实现：不产生副作用，且视为"成功"——
    // 若报失败，去重标记会被撤销，未配置的构建将在每次触发时反复重试，纯属空转
    @Test func disabledTransportSwallowsEverythingAndReportsSuccess() async {
        let transport = DisabledAnalyticsTransport()

        let first = await transport.send(name: "app_active", properties: [:])
        let second = await transport.send(name: "module_opened", properties: ["module": "music"])

        #expect(first)
        #expect(second)
    }
}
