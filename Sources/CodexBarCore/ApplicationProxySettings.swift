import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(macOS)
import Network
import WebKit
#endif

public struct ApplicationProxySettings: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case http
        case socks5
    }

    public static let defaultsKey = "applicationProxySettings"
    public var enabled = false
    public var kind: Kind = .http
    public var host = "127.0.0.1"
    public var port = 7890
    public var username = ""
    public var bypass = "localhost,127.0.0.1,::1,*.local"

    public init() {}

    public var validationMessage: String? {
        guard !self.host.isEmpty, !self.host.contains(where: \.isWhitespace),
              !self.host.contains(where: { "/@?#".contains($0) }),
              !self.host.contains("://")
        else { return "Enter a hostname or IP address without a URL scheme or path." }
        guard (1...65535).contains(self.port) else { return "Port must be between 1 and 65535." }
        return nil
    }

    public var excludedDomains: [String] {
        self.bypass.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func load(defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: self.defaultsKey),
              let settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return settings
    }

    public func save(defaults: UserDefaults) throws {
        try defaults.set(JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    public func environment(password: String) -> [String: String] {
        guard self.enabled, self.validationMessage == nil else { return [:] }
        var url = URLComponents()
        url.scheme = self.kind == .http ? "http" : "socks5h"
        url.host = self.host
        url.port = self.port
        if !self.username.isEmpty {
            url.user = self.username
            url.password = password
        }
        guard let address = url.string else { return [:] }
        var result: [String: String] = [:]
        for name in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"] {
            result[name] = address
            result[name.lowercased()] = address
        }
        result["NO_PROXY"] = self.excludedDomains.joined(separator: ",")
        result["no_proxy"] = result["NO_PROXY"]
        result["NODE_USE_ENV_PROXY"] = "1"
        if let data = try? JSONEncoder().encode(self) {
            result["CODEXBAR_APPLICATION_PROXY"] = String(data: data, encoding: .utf8)
        }
        return result
    }
}

/// One immutable launch snapshot. Existing sessions and subprocesses are changed by restarting the app.
public enum ApplicationNetworkProxy {
    private struct Snapshot: Sendable {
        var settings: ApplicationProxySettings
        var password: String
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var snapshot: Snapshot? = State.inheritedSnapshot()

        private static func inheritedSnapshot() -> Snapshot? {
            let environment = ProcessInfo.processInfo.environment
            guard let raw = environment["CODEXBAR_APPLICATION_PROXY"],
                  let data = raw.data(using: .utf8),
                  let settings = try? JSONDecoder().decode(ApplicationProxySettings.self, from: data)
            else { return nil }
            let address = environment["https_proxy"] ?? environment["HTTPS_PROXY"] ?? ""
            return Snapshot(settings: settings, password: URLComponents(string: address)?.password ?? "")
        }
    }

    private static let state = State()

    private static var snapshot: Snapshot? {
        self.state.lock.lock()
        defer { self.state.lock.unlock() }
        return self.state.snapshot
    }

    public static var isEnabled: Bool {
        self.snapshot?.settings.enabled == true
    }

    public static func configure(settings: ApplicationProxySettings, password: String = "") {
        self.state.lock.lock()
        self.state.snapshot = Snapshot(settings: settings, password: password)
        self.state.lock.unlock()
    }

    public static func childEnvironment(_ environment: [String: String]) -> [String: String] {
        guard let snapshot = self.snapshot else { return environment }
        return environment.merging(snapshot.settings.environment(password: snapshot.password)) { _, proxy in proxy }
    }

    public static func configuration(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        #if os(macOS)
        if let snapshot = self.snapshot, snapshot.settings.enabled {
            return self.configuration(configuration, settings: snapshot.settings, password: snapshot.password)
        }
        #endif
        return configuration
    }

    public static let sharedSession: URLSession = TestProcessSafety.isRunning
        ? .shared : URLSession(configuration: Self.configuration(.default))

    #if os(macOS)
    public static func configuration(
        _ configuration: URLSessionConfiguration,
        settings: ApplicationProxySettings,
        password: String) -> URLSessionConfiguration
    {
        if settings.enabled {
            configuration.proxyConfigurations = self.proxies(settings: settings, password: password)
        }
        return configuration
    }

    public static func proxies(settings: ApplicationProxySettings, password: String) -> [ProxyConfiguration] {
        guard settings.enabled, settings.validationMessage == nil,
              let port = NWEndpoint.Port(rawValue: UInt16(settings.port))
        else {
            guard settings.enabled else { return [] }
            var blocked = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: 1))
            blocked.allowFailover = false
            return [blocked]
        }
        let endpoint = NWEndpoint.hostPort(host: .init(settings.host), port: port)
        var proxy = settings.kind == .http
            ? ProxyConfiguration(httpCONNECTProxy: endpoint)
            : ProxyConfiguration(socksv5Proxy: endpoint)
        proxy.allowFailover = false
        proxy.excludedDomains = settings.excludedDomains
        if !settings.username.isEmpty {
            proxy.applyCredential(username: settings.username, password: password)
        }
        return [proxy]
    }

    @MainActor
    public static func configure(_ store: WKWebsiteDataStore) {
        guard let snapshot = self.snapshot, snapshot.settings.enabled else { return }
        self.configure(store, settings: snapshot.settings, password: snapshot.password)
    }

    @MainActor
    public static func configure(
        _ store: WKWebsiteDataStore,
        settings: ApplicationProxySettings,
        password: String)
    {
        if settings.enabled {
            store.proxyConfigurations = self.proxies(settings: settings, password: password)
        }
    }
    #endif
}
