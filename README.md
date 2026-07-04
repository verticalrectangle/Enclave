# Enclave — SwiftUI app

Native iOS client for oh-my-pi, ported faithfully from the `Enclave.html` prototype.
Vertical Rectangle brutalist-glass; **native `TabView`** (real iOS tab bar → Liquid
Glass on iOS 26). Dark = VR mono + amber. Light = Rosé Pine Dawn (gold).

## Run it

New iOS App (iOS 17+, SwiftUI lifecycle). Drop these files into the target:

| File | Role |
|---|---|
| `EnclaveApp.swift` | `@main`, one `ThemeStore` |
| `RootView.swift` | native `TabView` — Sessions / Activity / Trust; Pair + Lock covers |
| `Theme.swift` | VR + Rosé Pine Dawn tokens, `.glass()`, `LiveDot`, `SpecCell` |
| `Models.swift` | `UITurn` (wire shape) + sample session library + slash cmds |
| `SessionVM.swift` | streams the mock live; maps 1:1 to `EngineBridge` commands |
| `SessionsView.swift` | library, sort, glass cards, live current-action |
| `EditorView.swift` | the hero — transcript + composer + stop + edit→rewind |
| `TranscriptViews.swift` | tool cards, sys chips, advisor, ask, approval, image viewer |
| `ComposerParts.swift` | cycling `/` hints, slash palette, attach menu, chips |
| `TrustView.swift` | host spec grid + model routing + devices + `ModelSheet` |
| `Screens.swift` | Activity, Pair (my.omp.sh/join/access), Lock Screen Live Activity |

**Fonts:** add `VT323-Regular.ttf` to the target + Info.plist (`UIAppFonts`) for the
terminal voice; the system font stands in for Inter. Without VT323 the `.term()`
text falls back gracefully.

Builds and runs against the **mock data** as-is — every screen is live: open
`enclave-app` (running) to watch the stream, Stop, then edit a message to rewind;
open `silvertune-web` (waiting) for the approval bar + ask picker; `epsilver-site`
for image read/inspect/generate → tap to focus.

## Live omp — the real engine (`EngineBridge.swift`)

`EngineBridge.swift` is a full native **oh-my-pi collab guest client** — the Swift
port of `@oh-my-pi/collab-web`. It parses a `/collab` link, opens the relay
WebSocket (`?role=guest`), seals/opens **AES-256-GCM** frames (`COLLAB_PROTO 3`),
applies host frames in arrival order, and projects the omp transcript onto the
same `UITurn` shape the mock uses — so every existing view renders live data
unchanged. `SessionVM` gains a live mode; the mock path is untouched.

```swift
let client = GuestClient(link: "<my.omp.sh link or ws://…>", name: "iPhone")
EditorView(live: client, seed: seed)   // client.turns streams into the UI
client.sendPrompt("audit the reconnect backoff")   // steer the host agent
client.sendAbort()                                 // stop the current turn
```

**Connect from the app:** Sessions → **Pair a box** → paste the link from
`omp /collab` → **Connect Live**. Full links (48-byte key) get control; view
links (32-byte key) join read-only. Frames are sealed on-device — the relay
never sees plaintext.

**Test against the offline host** (from the oh-my-pi repo):

```
cd packages/collab-web && bun scripts/mock-host.ts --port 7466
# paste the printed ws://localhost:7466/r/<id>.<key> link into Pair
```

A launch seam auto-joins from the `ENCLAVE_COLLAB_LINK` env var (deep-link / e2e
testing): `SIMCTL_CHILD_ENCLAVE_COLLAB_LINK=<link> xcrun simctl launch … xyz.epsilver.enclave`.
