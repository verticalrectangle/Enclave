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

## Wire the real engine

Link `EnclaveCore.xcframework` (from `../scaffold`), add `EngineBridge.swift`, then
feed `EditorView` from `bridge.turns` instead of `SessionVM`. Both expose the same
`UITurn`/`Turn` shape, so it's a data-source swap, not a rewrite:

```swift
@StateObject var engine = EngineBridge()
// onAppear:
engine.connect(url: "ws://localhost:8787", token: "dev", joinCode: "8F2K-A3F2")
engine.prompt("wire the validator to the sealed relay")
// render engine.turns
```

Start the keyless host first: `cd ../scaffold/enclave-backend && bun run src/mock-host.ts`.
