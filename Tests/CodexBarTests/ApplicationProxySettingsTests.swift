import Foundation
import Testing
@testable import CodexBarCore
#if os(macOS)
import Network
import WebKit
#endif

struct ApplicationProxySettingsTests {
    @Test
    func `proxy defaults keep application networking unchanged`() {
        let settings = ApplicationProxySettings()
        #expect(!settings.enabled)
        #expect(settings.host == "127.0.0.1")
        #expect(settings.port == 7890)
        #expect(settings.environment(password: "secret").isEmpty)
    }

    @Test(arguments: [0, -1, 65536, Int.max])
    func `invalid ports cannot be exported to subprocesses`(port: Int) {
        var settings = ApplicationProxySettings()
        settings.enabled = true
        settings.port = port
        #expect(settings.validationMessage != nil)
        #expect(settings.environment(password: "").isEmpty)
    }

    @Test(arguments: ["", "http://localhost", "localhost/path", "user@host", "bad host", "host?query"])
    func `server field rejects URL and credential syntax`(host: String) {
        var settings = ApplicationProxySettings()
        settings.host = host
        #expect(settings.validationMessage != nil)
    }

    @Test
    func `subprocess URLs escape credentials and preserve local bypass`() throws {
        var settings = ApplicationProxySettings()
        settings.enabled = true
        settings.username = "user@company"
        let environment = settings.environment(password: "p@ss:/?# word")
        let address = try #require(environment["HTTPS_PROXY"])
        let url = try #require(URLComponents(string: address))
        #expect(url.user == settings.username)
        #expect(url.password == "p@ss:/?# word")
        #expect(url.host == settings.host)
        #expect(url.port == 7890)
        #expect(environment["https_proxy"] == address)
        #expect(environment["NO_PROXY"] == settings.bypass)
        let json = try #require(environment["CODEXBAR_APPLICATION_PROXY"])
        #expect(!json.contains("p@ss"))
        #expect(try JSONDecoder().decode(ApplicationProxySettings.self, from: Data(json.utf8)) == settings)
    }

    @Test
    func `SOCKS subprocesses resolve names at the proxy`() {
        var settings = ApplicationProxySettings()
        settings.enabled = true
        settings.kind = .socks5
        #expect(settings.environment(password: "")["ALL_PROXY"] == "socks5h://127.0.0.1:7890")
    }

    #if os(macOS)
    /// The Swift overlay getter returns [] on macOS 15/26 even after a successful set.
    /// Inspect the native object consumed by URLSession and WebKit instead.
    private static func storedExcludedDomains(_ proxy: ProxyConfiguration) -> [String] {
        var domains: [String] = []
        nw_proxy_config_enumerate_excluded_domains(proxy._nw) { domains.append(String(cString: $0)) }
        return domains
    }

    @Test(arguments: ApplicationProxySettings.Kind.allCases)
    func `native proxies preserve bypass and prohibit direct failover`(kind: ApplicationProxySettings.Kind) throws {
        var settings = ApplicationProxySettings()
        settings.enabled = true
        settings.kind = kind
        settings.bypass = "localhost, 127.0.0.1,\n*.example.com"
        let proxy = try #require(ApplicationNetworkProxy.proxies(settings: settings, password: "").first)
        #expect(!proxy.allowFailover)
        #expect(Self.storedExcludedDomains(proxy) == ["localhost", "127.0.0.1", "*.example.com"])
        settings.enabled = false
        #expect(ApplicationNetworkProxy.proxies(settings: settings, password: "").isEmpty)
    }

    @Test
    func `app session configuration retains provider isolation and applies proxy`() throws {
        var settings = ApplicationProxySettings()
        settings.enabled = true
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        let applied = ApplicationNetworkProxy.configuration(configuration, settings: settings, password: "")
        #expect(applied === configuration)
        #expect(applied.urlCredentialStorage == nil)
        #expect(applied.httpCookieStorage == nil)
        #expect(applied.proxyConfigurations.count == 1)
        #expect(try #require(applied.proxyConfigurations.first).allowFailover == false)
    }

    @Test @MainActor
    func `embedded websites receive the same native proxy policy`() throws {
        var settings = ApplicationProxySettings()
        settings.enabled = true
        let store = WKWebsiteDataStore.nonPersistent()
        ApplicationNetworkProxy.configure(store, settings: settings, password: "")
        #expect(store.proxyConfigurations.count == 1)
        let proxy = try #require(store.proxyConfigurations.first)
        #expect(!proxy.allowFailover)
        #expect(Self.storedExcludedDomains(proxy) == settings.excludedDomains)
    }

    @Test
    func `invalid persisted proxy fails closed instead of returning direct configuration`() throws {
        var settings = ApplicationProxySettings()
        settings.enabled = true
        settings.port = -1
        let proxies = ApplicationNetworkProxy.proxies(settings: settings, password: "")
        #expect(proxies.count == 1)
        #expect(try #require(proxies.first).allowFailover == false)
    }
    #endif
}
