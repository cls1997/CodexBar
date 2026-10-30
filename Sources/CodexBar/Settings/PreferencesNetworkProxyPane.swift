import AppKit
import CodexBarCore
import Network
import SwiftUI

@MainActor
struct NetworkProxyPane: View {
    @State private var proxy = ApplicationProxySettings.load(defaults: .standard)
    @State private var password = ""
    @State private var clearPassword = false
    @State private var status: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                Toggle(L("Use an application proxy"), isOn: self.$proxy.enabled)
                Text(L("proxy_scope_description"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Picker(L("Proxy type"), selection: self.$proxy.kind) {
                    Text(verbatim: "HTTP").tag(ApplicationProxySettings.Kind.http)
                    Text(verbatim: "SOCKS5").tag(ApplicationProxySettings.Kind.socks5)
                }
                TextField(L("Server"), text: self.$proxy.host)
                TextField(L("Port"), value: self.$proxy.port, format: .number.grouping(.never))
                TextField(L("Username (optional)"), text: self.$proxy.username)
                SecureField(L("Password (leave blank to keep saved password)"), text: self.$password)
                Toggle(L("Remove saved proxy password"), isOn: self.$clearPassword)
            } header: {
                Text(L("Proxy server"))
            } footer: {
                SettingsSectionFooter(
                    L("proxy_password_storage"))
            }
            .disabled(!self.proxy.enabled)
            Section {
                TextField(L("Bypass addresses"), text: self.$proxy.bypass, axis: .vertical)
                    .lineLimit(2...4)
            } footer: {
                SettingsSectionFooter(
                    L("proxy_bypass_help"))
            }
            .disabled(!self.proxy.enabled)
            Section {
                HStack {
                    Button(L("Save proxy settings")) { self.save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(self.isTesting || (self.proxy.enabled && self.proxy.validationMessage != nil))
                    Button(L("Test connection")) { Task { await self.testConnection() } }
                        .disabled(!self.proxy.enabled || self.proxy.validationMessage != nil || self.isTesting)
                    if self.isTesting { ProgressView().controlSize(.small) }
                }
                if self.proxy.enabled, let message = self.proxy.validationMessage {
                    Text(message).foregroundStyle(.red).font(.callout)
                }
                if let status = self.status {
                    Text(status).font(.callout).textSelection(.enabled)
                }
            } footer: {
                SettingsSectionFooter(
                    L(
                        "proxy_restart_required"))
            }
            Section {
                Text(
                    L(
                        "proxy_system_components_paused"))
                Text(
                    L(
                        "proxy_external_tools_coverage"))
                Text(
                    L(
                        "proxy_tls_policy"))
            } header: {
                Text(L("Coverage"))
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func resolvedPassword() throws -> String {
        if self.clearPassword { return "" }
        if !self.password.isEmpty { return self.password }
        guard !self.proxy.username.isEmpty else { return "" }
        guard let saved = try ApplicationProxyPasswordStore.load() else {
            throw ApplicationProxyPasswordStore.StoreError.unavailable
        }
        return saved
    }

    private func save() {
        do {
            if self.proxy.enabled, let message = self.proxy.validationMessage {
                self.status = message
                return
            }
            if self.clearPassword || !self.password.isEmpty {
                try ApplicationProxyPasswordStore.save(self.clearPassword ? "" : self.password)
            } else if self.proxy.enabled, !self.proxy.username.isEmpty {
                _ = try self.resolvedPassword()
            }
            try self.proxy.save(defaults: .standard)
            self.password = ""
            self.clearPassword = false
            self.status = L("Saved. Restart CodexBar to apply the proxy settings.")
        } catch {
            self.status = error.localizedDescription
        }
    }

    private func testConnection() async {
        self.isTesting = true
        self.status = nil
        defer { self.isTesting = false }
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.proxyConfigurations = try ApplicationNetworkProxy.proxies(
                settings: self.proxy, password: self.resolvedPassword())
            configuration.urlCredentialStorage = nil
            configuration.httpCookieStorage = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!)
            request.timeoutInterval = 15
            let start = Date()
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                self.status = L("Proxy test failed: unexpected server response.")
                return
            }
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            self.status = L("Proxy test succeeded.") + " HTTP \(http.statusCode), \(elapsed) ms"
        } catch {
            self.status = L("Proxy test failed.") + " " + error.localizedDescription
        }
    }
}
