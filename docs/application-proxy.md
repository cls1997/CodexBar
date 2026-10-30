---
summary: Application-wide proxy settings and transport coverage.
read_when:
  - Configuring a proxy for all providers
  - Working on HTTP, WebKit, or subprocess transports
---

# Application proxy

Open Settings → Network & Proxy. Enable the application proxy, select HTTP or
SOCKS5, and enter the server and port. A typical local proxy is `127.0.0.1:7890`.
Do not put a URL scheme in the server field. Optional username and password
support authenticated proxies. Passwords are stored in a dedicated macOS
Keychain item and are excluded from saved preferences and exported settings.
A blank password field preserves the saved password; the removal option deletes it.

Save, then restart CodexBar. The app captures one configuration at launch so
HTTP sessions, embedded websites and new helper processes use the same policy.
The Test connection button checks the unsaved configuration against Apple's
HTTPS connectivity page, without provider credentials or browser cookies.
It does not prove that a particular provider or external tool can connect.

## Coverage

- All app-owned URLSession creation paths use `ApplicationNetworkProxy`, including
  provider requests, OAuth refreshes, plugin requests, exchange rates, pricing and
  Homebrew metadata requests. Their existing cookies, caches and redirect policies
  remain provider-specific.
- Both embedded WebKit view creation paths apply the same proxy to the relevant
  website data store, including account-specific stores.
- Subprocess and PTY launch paths receive uppercase and lowercase HTTP_PROXY,
  HTTPS_PROXY, ALL_PROXY and NO_PROXY, plus the launch snapshot for CodexBar helpers.
  SOCKS URLs use `socks5h` for remote name resolution. Proxy credentials are escaped
  in the child environment; never log these values. Third-party tools must support
  those variables; this feature cannot force arbitrary external sockets through a
  proxy. `NODE_USE_ENV_PROXY=1` is supplied for Node versions that support it.
- Built-in Sparkle and Homebrew update checks/downloads/installations are disabled
  in this edition regardless of proxy state. Manage upgrades using your own Homebrew tap.
  CloudKit sync is disabled in this proxy edition regardless of proxy state;
  its settings entry and remote fleet accounts are hidden. Existing local settings,
  cached data and cloud records are retained. Local preferences imports still work.
- External browsers and OS services are outside this application configuration.
  This is application proxy support, not a per-app VPN or firewall.

The default bypass list is `localhost,127.0.0.1,::1,*.local`, preserving access to
local agent APIs. Edit it using comma-separated host/domain patterns. These are native domain exceptions,
not a CIDR or regular-expression matcher. macOS may independently exempt loopback
connections even if they are removed from the list; local services are not an
appropriate target for testing whether public traffic can fall back directly.

Native HTTP CONNECT and SOCKS5 connections use Apple's Network framework with
`allowFailover=false`: proxy failures do not silently retry directly. TLS trust
checks remain enabled. Invalid persisted enabled configurations use an unreachable
local proxy rather than a direct session. External tool behavior depends on that tool.

The upstream build defaults to proxy disabled. This local test build is configured
through its settings page; the source does not hard-code a user's proxy address.
Automatic updates are also disabled by the repository's normal ad-hoc signing flow.
