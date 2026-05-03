# tvOSProxyMan

A fully functional HTTPS/HTTP web debugging proxy that runs natively on Apple TV (tvOS 17+). Intercept, inspect, and manipulate network traffic from any device on your LAN — no Mac required once deployed.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [Root CA Installation](#root-ca-installation)
- [Configuring Devices to Use the Proxy](#configuring-devices-to-use-the-proxy)
- [UI Walkthrough](#ui-walkthrough)
- [Breakpoints](#breakpoints)
- [Map Local](#map-local)
- [Troubleshooting](#troubleshooting)
- [Folder Structure](#folder-structure)
- [Architecture Overview](#architecture-overview)

---

## Features

- **HTTPS MITM** — Full TLS interception via a locally generated Root CA and per-hostname leaf certificates
- **HTTP proxying** — Plain HTTP requests captured and displayed
- **3-column tvOS UI** — Host sidebar → request list → detail inspector, all navigable via Siri Remote
- **Breakpoints** — Pause matching requests mid-flight; forward, drop, or edit & resend on the Apple TV
- **Map Local** — Return a static JSON/text response for any URL pattern without hitting the real server
- **Real-time traffic** — Transactions appear as they occur; status badges update live
- **Request detail** — Overview metrics, full request/response headers, body viewer with JSON pretty-printing

---

## Requirements

| Requirement | Detail |
|---|---|
| Apple TV | 4th gen or later, tvOS 17.0+ |
| Xcode | 16.0+ (uses `PBXFileSystemSynchronizedRootGroup`) |
| Swift | 5.9+ (`@Observable` macro) |
| Client devices | Any device that supports manual HTTP proxy configuration |

---

## Quick Start

1. **Clone / open** the project in Xcode.
2. Set your **Development Team** in *Signing & Capabilities* 
3. Select your Apple TV (or the tvOS 18.x simulator) as the run destination.
4. **Run** (`⌘R`). The proxy starts automatically on port **9090**.
5. Note the Apple TV's IP address (Settings → Network on the Apple TV, or check your router).
6. [Configure client devices](#configuring-devices-to-use-the-proxy) to route traffic through the proxy.
7. [Install the Root CA](#root-ca-installation) on each client device to avoid TLS trust errors.

---

## How It Works

```
Client Device
    │  HTTP / CONNECT tunnel
    ▼
tvOSProxyMan (port 9090)
    │
    ├─ Plain HTTP ──────────────────────────────► Origin Server
    │      capture → Map Local? → Breakpoint? → forward
    │
    └─ HTTPS (CONNECT) ───► per-host MITM TLS listener (ephemeral port)
           │                   leaf cert signed by Root CA
           │   decrypted HTTP
           ▼
       MITMConnection
           capture → Map Local? → Breakpoint? → origin via TLS
```

### MITM TLS Bridge

1. Client sends `CONNECT host:443 HTTP/1.1`.
2. Proxy replies `200 Connection Established`.
3. An ephemeral `NWListener` is created with a TLS configuration using a freshly generated (or cached) leaf certificate for that hostname, signed by the Root CA.
4. The existing client TCP connection is piped (plain TCP) into the ephemeral listener. The listener's TLS stack decrypts the traffic.
5. Decrypted plaintext HTTP arrives at `MITMConnection`, which runs the full Map Local → Breakpoint → origin pipeline.
6. Responses from the real origin are relayed back through the same path.

---

## Root CA Installation

The proxy generates a P-256 Root CA on first launch and stores it in the device keychain. Clients must trust this CA to avoid TLS errors.

### Exporting the Root CA

The Root CA DER bytes are available at runtime via:
```swift
CertificateManager.shared.rootCACertificateDER  // Data?
```

**Planned / manual export options:**
- Add a "Share CA" button in the app that AirDrops the `.cer` file to nearby devices.
- Serve the cert over HTTP on a secondary port (e.g. `http://<apple-tv-ip>:9091/ca.cer`).
- For the simulator: find the cert in the app's keychain via Instruments or the Security framework and export it manually.

### Installing on iOS / iPadOS

1. Receive the `.cer` file (AirDrop, Safari download, etc.).
2. Tap the file — iOS prompts "Profile Downloaded". Go to **Settings → General → VPN & Device Management** and tap the profile to install it.
3. Go to **Settings → General → About → Certificate Trust Settings** and toggle the tvOSProxyMan Root CA to **full trust**.

### Installing on macOS

1. Double-click the `.cer` file — Keychain Access opens.
2. Add to the **System** keychain.
3. Find "tvOSProxyMan Root CA", double-click, expand *Trust*, set **"When using this certificate"** to **Always Trust**.

### Installing on Android

1. Transfer the `.cer` to the device.
2. **Settings → Security → Install a certificate → CA certificate**.

---

## Configuring Devices to Use the Proxy

Set the **HTTP Proxy** on the client device to:

| Field | Value |
|---|---|
| Server | Apple TV's IP address (e.g. `192.168.1.42`) |
| Port | `9090` |
| Authentication | Off |

### iOS / iPadOS

**Settings → Wi-Fi → [your network] → Configure Proxy → Manual**

### macOS

**System Settings → Network → [interface] → Details → Proxies**
Enable "Web Proxy (HTTP)" and "Secure Web Proxy (HTTPS)", both pointing to the Apple TV IP:9090.

### Android

**Settings → Wi-Fi → [long-press network] → Modify Network → Advanced → Proxy → Manual**

---

## UI Walkthrough

```
┌─────────────────┬──────────────────┬──────────────────────────────┐
│  Host Sidebar   │  Request List    │  Transaction Detail          │
│                 │                  │                              │
│ ● api.github.com│ GET  /repos      │ [Overview] [Request] [Response]
│   14 requests   │ POST /graphql    │                              │
│ ● cdn.example.. │ GET  /assets/..  │  URL  https://api.github.com/│
│   3 requests    │ GET  /users/me   │  Method  GET                 │
│                 │                  │  Status  200                 │
│  [Rules]  [▶]   │                  │  Duration  142 ms            │
└─────────────────┴──────────────────┴──────────────────────────────┘
```

### Toolbar (left column)

| Button | Action |
|---|---|
| **Rules (N)** | Opens the Breakpoints / Map Local sheet |
| **▶ Start / ■ Stop** | Starts or stops the proxy listener on port 9090 |
| **Trash** | Clears all captured transactions |

### Siri Remote Navigation

- **Swipe left/right** on the remote to move between columns.
- **Click** to select a host or request.
- **Swipe up/down** in detail column to scroll.
- **Swipe left/right** in the detail column to switch tabs (Overview / Request / Response).

---

## Breakpoints

Breakpoints pause matching HTTP(S) requests before they reach the origin server.

### Adding a Breakpoint

1. Press **Rules** in the top-left toolbar.
2. Tap **+** to add a new breakpoint.
3. Enter a **URL pattern**:
   - Bare string: matches as substring → `api.example.com` matches any URL containing that string.
   - Glob: `*` matches any run of characters → `*.example.com/api/*` matches all API calls.
4. Optionally limit to specific **methods** (e.g. `GET, POST`). Leave blank to match all.
5. Tap **Add**.

### When a Breakpoint Fires

A full-screen modal appears with:

| Panel | Content |
|---|---|
| Left | Request method, URL, all headers, body |
| Right | **Forward** / **Drop** / **Edit & Forward** actions |

- **Forward** — Send the original request unmodified.
- **Drop** — Respond to the client with `503 Dropped by Breakpoint`.
- **Edit & Forward** — Modify the request body, then send.

The network connection is suspended (via `CheckedContinuation`) until you make a choice. The proxy listener remains active for other connections during this time.

---

## Map Local

Map Local rules intercept matching requests and return a static response immediately, without contacting the origin server.

### Adding a Map Local Rule

1. Press **Rules** → switch to the **Map Local** tab.
2. Tap **+**.
3. Enter:
   - **URL pattern** (same glob syntax as breakpoints)
   - **Status code** (default: 200)
   - **Content-Type** (default: `application/json`)
   - **Response body** (JSON or any text)
4. Tap **Add**.

### Use Cases

- Mock a backend endpoint during development.
- Test error states (return 500, 404, etc.).
- Inject latency-free responses for UI testing.
- Override A/B test flags.

---

## Troubleshooting

### Proxy starts but no traffic appears

- Confirm the client device's proxy is set to the correct IP and port 9090.
- Make sure the Apple TV and client are on the **same Wi-Fi network**.
- Some apps bypass the system proxy. Apps using `URLSession` with default configuration respect the system proxy; apps using custom networking stacks or certificate pinning may not.

### HTTPS requests show as "TLS" (tunneled, not decrypted)

The proxy fell back to transparent TCP tunneling. This happens when:

1. **Root CA not installed / trusted** on the client — the client rejects the leaf cert and the TLS handshake fails before the proxy can read traffic.
2. **Certificate pinning** — the app validates the server's exact certificate hash. tvOSProxyMan cannot bypass pinning without additional tooling.
3. **First-launch cert generation** — leaf certs are generated on demand. If the proxy started less than 1 second ago, it may still be initializing. Retry the request.

### "Proxy listening on :9,090" shows a comma in the port number

This is a SwiftUI number-formatting quirk on some locales. The actual port is 9090. The `listeningPort` is a `UInt16` passed to a `Text` interpolation — fix by formatting it explicitly: `Text("Port: \(store.listeningPort, format: .number.grouping(.never))")` in `SidebarEmptyView`.

### App crashes on first launch

The certificate manager initializes asynchronously in a `Task.detached`. If it throws, the error is silently swallowed and MITM falls back to transparent tunneling. Check Console.app with the subsystem filter `com.tvOSProxyMan` for details.

### Requests pile up / modal gets stuck

If you stop the proxy while a breakpoint modal is open, `BreakpointEngine.shared.dropAll()` is called automatically to resolve dangling continuations. If you dismiss the app abnormally, those continuations are abandoned and the network calls on the client will time out.

### Build error: "Multiple commands produce .stringsdata"

This means there are two Swift files with the same filename stem in the module. The root-level stub files (e.g. `ContentView.swift`) must be listed in the `PBXFileSystemSynchronizedBuildFileExceptionSet` in the `.xcodeproj`. Check that `membershipExceptions` in the project file includes all 15 stub filenames.

---

## Folder Structure

```
tvOSProxyMan/
├── App/
│   └── tvOSProxyManApp.swift          # @main entry point, boots ProxyServer
│
├── Proxy/
│   ├── Core/
│   │   ├── ProxyServer.swift          # NWListener on :9090, connection registry
│   │   ├── ProxyConnection.swift      # One client session: HTTP dispatch + MITM setup
│   │   └── MITMConnection.swift       # Decrypted HTTPS handler: pipeline + origin relay
│   ├── Models/
│   │   ├── HTTPHeaderField.swift      # Sendable name/value pair
│   │   ├── TransactionState.swift     # pending/active/complete/failed/tunneled
│   │   └── ProxyTransaction.swift     # Full request+response snapshot
│   ├── Certificate/
│   │   ├── CertificateError.swift     # Typed errors from cert operations
│   │   ├── DEREncoder.swift           # Minimal ASN.1 DER encoder for X.509 v3
│   │   └── CertificateManager.swift   # Root CA gen/keychain + per-host leaf certs
│   └── Rules/
│       ├── Breakpoint/
│       │   ├── Breakpoint.swift       # Rule model (pattern + methods + enabled flag)
│       │   ├── BreakpointAction.swift # forward / drop / forwardModified
│       │   ├── PausedRequest.swift    # Suspended request holding CheckedContinuation
│       │   └── BreakpointEngine.swift # @Observable singleton, async suspension logic
│       └── MapLocal/
│           ├── MapLocalRule.swift     # Rule model + LocalResponse builder
│           └── MapLocalEngine.swift   # @Observable singleton, synchronous intercept
│
├── Session/
│   ├── HostSummary.swift              # Per-host aggregated stats for sidebar
│   └── ProxySessionStore.swift        # @Observable view-model, selection + filter state
│
├── Utilities/
│   └── PatternMatcher.swift           # patternMatches() free function (glob + substring)
│
└── Views/
    ├── Root/
    │   └── ContentView.swift          # NavigationSplitView root + breakpoint overlay
    ├── Sidebar/
    │   ├── HostSidebarView.swift       # Column 1: host list + toolbar
    │   ├── SidebarEmptyView.swift      # Empty state (listening / stopped / error)
    │   └── HostRowView.swift           # One host row: color dot, count, status badge
    ├── RequestList/
    │   ├── RequestListView.swift       # Column 2: filtered transaction list
    │   └── RequestRowView.swift        # One request row: method badge, path, duration
    ├── Detail/
    │   ├── TransactionDetailView.swift # Column 3: tab bar container
    │   ├── OverviewTab.swift           # URL card + metric tiles + timing
    │   ├── RequestTab.swift            # Request headers + body
    │   ├── ResponseTab.swift           # Response headers + body
    │   └── Components/
    │       ├── InfoCard.swift          # Titled material card
    │       ├── MetricTile.swift        # Single large-value metric cell
    │       ├── HeadersTable.swift      # Focusable header name/value table
    │       └── BodyView.swift          # Pretty-printed JSON / text / hex body viewer
    ├── Breakpoint/
    │   ├── BreakpointModalView.swift   # Full-screen paused request modal
    │   ├── BreakpointHeaderSection.swift  # URL + method badge at top of modal
    │   ├── BreakpointReadOnlySection.swift # Headers + body read-only view
    │   ├── BreakpointEditSection.swift    # Editable body TextField
    │   └── Components/
    │       ├── ActionCard.swift        # Forward / Drop / Edit action button card
    │       ├── SectionTitle.swift      # Small bold section label
    │       └── HeaderLine.swift        # name : value header row
    ├── Rules/
    │   ├── ProxyRulesView.swift        # Sheet: manual tab bar + add button
    │   ├── BreakpointsListView.swift   # Breakpoint list with swipe-to-delete
    │   ├── BreakpointRowView.swift     # One breakpoint row with toggle
    │   ├── MapLocalListView.swift      # Map Local rule list with swipe-to-delete
    │   ├── MapLocalRowView.swift       # One rule row: status code + content type
    │   ├── AddBreakpointSheet.swift    # URL pattern + methods form
    │   ├── AddMapLocalSheet.swift      # URL + status + content-type + body form
    │   └── TabBarButton.swift          # Custom tab bar button (Breakpoints / Map Local)
    └── Shared/
        ├── MethodBadge.swift           # Coloured HTTP method pill (GET=blue, POST=green…)
        ├── StatusBadge.swift           # HTTP status code pill with progress/error states
        └── EmptyDetailPlaceholder.swift # "Select a Request" placeholder
```

---

## Architecture Overview

### Data Flow

```
NWListener (port 9090)
    └─► ProxyServer.newConnectionHandler
            └─► ProxyConnection.start()
                    ├─ HTTP  ─► forwardHTTP()
                    │               Task {
                    │                   await MapLocalEngine.localResponse() → serve or skip
                    │                   await BreakpointEngine.checkIfBreakpointHit() → suspend or skip
                    │                   NWConnection to origin → relayHTTPResponse()
                    │               }
                    └─ HTTPS ─► startMITM()
                                    NWListener (ephemeral TLS port, leaf cert)
                                        └─► MITMConnection.start()
                                                Task {
                                                    await MapLocalEngine.localResponse() → serve or skip
                                                    await BreakpointEngine.checkIfBreakpointHit() → suspend or skip
                                                    NWConnection to origin (.tls) → relayAndCaptureResponse()
                                                }
```

### Concurrency Model

| Layer | Isolation |
|---|---|
| `ProxyServer`, `ProxySessionStore`, `BreakpointEngine`, `MapLocalEngine` | `@MainActor` `@Observable` — mutated only on the main actor |
| `ProxyConnection`, `MITMConnection` | Non-isolated — runs on `networkQueue` (a serial `DispatchQueue`) |
| Bridging (capture, updateTransaction) | `nonisolated` methods that dispatch `Task { @MainActor in … }` |
| Breakpoint suspension | `withCheckedContinuation` in an async `Task` — suspends the network Task without blocking the queue |

### Certificate Lifecycle

1. On first `ProxyServer.start()`, `CertificateManager.initialize()` runs in a `Task.detached`.
2. If no Root CA exists in the keychain, a P-256 key pair and self-signed X.509 v3 certificate are generated using the custom `DEREncoder` + Security framework `SecKeyCreateSignature`.
3. Leaf certificates are generated on demand per hostname and cached in memory for the session lifetime.
4. Key-cert pairing in the keychain uses `kSecAttrApplicationLabel = SHA-1(publicKeyPoint)` — the same hash Security.framework computes from the cert's public key for automatic `SecIdentity` construction.
