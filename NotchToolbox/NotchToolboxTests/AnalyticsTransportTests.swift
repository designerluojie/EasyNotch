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
        // Umami 没有 User-Agent 会直接拒绝请求
        let userAgent = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(userAgent.isEmpty == false)

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
