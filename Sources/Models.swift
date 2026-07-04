//  Models.swift
//  UI-side value types + the mock session library. In the live app the transcript
//  comes from EngineBridge.turns (decoded from the C++ reconciler); these sample
//  sessions stand in until the engine is connected, and match the wire turn shapes
//  1:1 so swapping to live data changes nothing in the views.

import SwiftUI

// MARK: - Turn (matches EngineBridge.Turn / the reconciler's UI events)

struct UITurn: Identifiable, Equatable {
    let id: String
    var type: TurnType
    var text: String = ""
    var streaming = false
    var image: String? = nil

    // tool / sys
    var kind: String = ""          // tool kind or sys kind
    var head: String = ""
    var meta: String = ""
    var add: Int? = nil
    var del: Int? = nil
    var lines: [String] = []
    var caption: String? = nil

    // ask / permission
    var question: String = ""
    var options: [String] = []
    var pending = false

    static func == (a: UITurn, b: UITurn) -> Bool {
        a.id == b.id && a.text == b.text && a.streaming == b.streaming && a.pending == b.pending
    }
}

enum TurnType: String { case user, agent, tool, advisor, sys, ask, permission }

// tool-kind → sf symbol + color
func toolGlyph(_ kind: String) -> String {
    switch kind {
    case "read": return "doc.text"
    case "search", "ast_grep", "find": return "magnifyingglass"
    case "edit", "write", "ast_edit": return "square.and.pencil"
    case "bash", "eval": return "terminal"
    case "lsp": return "chevron.left.forwardslash.chevron.right"
    case "task": return "circle.grid.cross"
    case "debug": return "ladybug"
    case "inspect": return "eye"
    case "image": return "photo"
    default: return "doc.text"
    }
}
func toolColor(_ kind: String, _ t: Theme) -> Color {
    switch kind {
    case "edit", "write", "ast_edit": return t.cEdit
    case "bash", "eval": return t.cBash
    case "lsp": return t.cLsp
    case "task": return t.cTask
    case "inspect", "debug": return t.cLsp
    case "image": return t.cTask
    default: return t.txtMuted
    }
}

// MARK: - Session

struct Session: Identifiable {
    let id: String
    let repo: String
    let branch: String
    let dir: String
    let model: String
    let role: String
    var status: Status          // running / waiting / idle
    let lastSeen: String
    let action: String
    let tokens: String
    let cost: String
    var turns: [UITurn]

    enum Status: String { case running, waiting, idle }
}

// MARK: - Model routing (omp config: role → model + thinking)

struct RoleRoute: Identifiable {
    var id: String { role }
    let role: String
    var model: String
    var thinking: String
    let note: String
}

struct ModelChoice: Identifiable { var id: String { modelId }; let modelId: String; let prov: String; let name: String }

// MARK: - Sample data

enum Sample {
    static let host = (name: "studio-mini", os: "macOS 15.4 · Apple M4", omp: "omp 16.3.4",
                       relay: "my.omp.sh", surface: "32 tools · 14 lsp · 28 dap",
                       core: "40+ providers · ~55k Rust",
                       fingerprint: "A3F2 91C4 7E08 BB19 5D6A 2F31 C0E4 88AA", paired: "Jul 2, 2026")

    static func tool(_ kind: String, _ head: String, _ meta: String, add: Int? = nil, del: Int? = nil,
                     lines: [String] = [], image: String? = nil, caption: String? = nil, pending: Bool = false) -> UITurn {
        var t = UITurn(id: UUID().uuidString, type: .tool)
        t.kind = kind; t.head = head; t.meta = meta; t.add = add; t.del = del
        t.lines = lines; t.image = image; t.caption = caption; t.pending = pending
        return t
    }
    static func user(_ s: String, image: String? = nil) -> UITurn { var t = UITurn(id: UUID().uuidString, type: .user); t.text = s; t.image = image; return t }
    static func agent(_ s: String) -> UITurn { var t = UITurn(id: UUID().uuidString, type: .agent); t.text = s; return t }
    static func advisor(_ s: String) -> UITurn { var t = UITurn(id: UUID().uuidString, type: .advisor); t.text = s; return t }
    static func sys(_ kind: String, _ s: String) -> UITurn { var t = UITurn(id: UUID().uuidString, type: .sys); t.kind = kind; t.text = s; return t }
    static func ask(_ q: String, _ opts: [String]) -> UITurn { var t = UITurn(id: UUID().uuidString, type: .ask); t.question = q; t.options = opts; return t }
    static func perm(_ meta: String, add: Int, del: Int) -> UITurn { var t = UITurn(id: UUID().uuidString, type: .permission); t.meta = meta; t.add = add; t.del = del; t.pending = true; return t }

    static let sessions: [Session] = [
        Session(id: "s1", repo: "enclave-app", branch: "acp-relay", dir: "~/vr/enclave",
                model: "DeepSeek V4 Pro", role: "default", status: .running, lastSeen: "now",
                action: "RUNNING RECONNECT FUZZ", tokens: "84K", cost: "$1.42", turns: [
            user("wire the ACP frame validator to the sealed relay and add a reconnect with heartbeat"),
            agent("Reading the bridge and the ACP schema before I touch the socket."),
            tool("read", "read", "RelayClient.swift · 128 lines"),
            tool("search", "ast_grep", "\"func send(\" · 3 hits"),
            agent("Unknown frame kinds should be rejected before they reach the wire. Adding a schema guard in send()."),
            tool("edit", "edit · hashline", "RelayClient.swift", add: 12, del: 3,
                 lines: ["+ guard Contract.validate(frame) else {", "+     throw RelayError.invalidFrame(frame.kind)", "+ }", "  try socket.write(frame.sealed())"]),
            advisor("You're not handling the half-open socket — if the box sleeps, writes will hang. Add a heartbeat timeout."),
            tool("bash", "$ swift build", "ok · 8.2s"),
            tool("lsp", "lsp · diagnostics", "0 errors · 0 warnings"),
        ]),
        Session(id: "s2", repo: "silvertune-web", branch: "wasm-simd", dir: "~/vr/silvertune-web",
                model: "GLM-5.2", role: "plan", status: .waiting, lastSeen: "2 min ago",
                action: "WAITING · APPROVE EDIT", tokens: "51K", cost: "$0.88", turns: [
            user("port the pitch shifter hot loop to wasm simd"),
            tool("read", "read", "shifter.c · 240 lines"),
            ask("Which SIMD width should I target?", ["128-bit · v128 ×4", "256-bit · relaxed ×8"]),
            perm("shifter_simd.c", add: 46, del: 0),
        ]),
        Session(id: "s3", repo: "digital-prayer", branch: "main", dir: "~/vr/digital-prayer",
                model: "DeepSeek V4 Flash", role: "smol", status: .idle, lastSeen: "1 hr ago",
                action: "IDLE", tokens: "9K", cost: "$0.06", turns: [
            user("why does the cross flicker on cold boot"),
            tool("read", "read", "led.rs · 88 lines"),
            tool("bash", "$ journalctl -u prayer", "3 undervoltage events"),
            agent("The panel draws before the 5V rail settles. Gate the first frame on a 200ms rail-good check."),
        ]),
        Session(id: "s5", repo: "epsilver-site", branch: "og-cards", dir: "~/vr/epsilver-site",
                model: "Kimi K2.7 Code", role: "designer", status: .idle, lastSeen: "12 min ago",
                action: "IDLE", tokens: "38K", cost: "$0.44", turns: [
            user("match the hero to this reference, then regenerate the OG card", image: "https://picsum.photos/seed/enclaveref/640/400"),
            tool("read", "read", "reference.png · 640×400", image: "https://picsum.photos/seed/enclaveref/640/400"),
            tool("inspect", "inspect_image", "reference.png", image: "https://picsum.photos/seed/enclaveref/640/400",
                 caption: "Centered wordmark on a dark hero, one accent, generous top padding. Hairline nav, right-aligned."),
            agent("Centered lockup, single accent, hairline nav. Regenerating the OG card."),
            tool("image", "generate_image", "og-card.png · 1200×630", image: "https://picsum.photos/seed/enclaveog/1200/630"),
        ]),
    ]

    static let roles: [RoleRoute] = [
        .init(role: "default",  model: "deepseek/deepseek-v4-pro",             thinking: "xhigh",   note: "main coding turns"),
        .init(role: "slow",     model: "deepseek/deepseek-v4-pro",             thinking: "xhigh",   note: "hard problems"),
        .init(role: "smol",     model: "deepseek/deepseek-v4-flash",           thinking: "minimal", note: "quick small edits"),
        .init(role: "commit",   model: "deepseek/deepseek-v4-pro",             thinking: "high",    note: "conventional commits"),
        .init(role: "plan",     model: "openrouter/z-ai/glm-5.2",              thinking: "xhigh",   note: "plan mode"),
        .init(role: "advisor",  model: "openrouter/z-ai/glm-5.2",              thinking: "xhigh",   note: "reviewer notes"),
        .init(role: "designer", model: "openrouter/moonshotai/kimi-k2.7-code", thinking: "high",    note: "UI / UX work"),
    ]

    static let catalog: [ModelChoice] = [
        .init(modelId: "deepseek/deepseek-v4-pro",             prov: "deepseek",   name: "DeepSeek V4 Pro"),
        .init(modelId: "deepseek/deepseek-v4-flash",           prov: "deepseek",   name: "DeepSeek V4 Flash"),
        .init(modelId: "openrouter/z-ai/glm-5.2",              prov: "openrouter", name: "GLM-5.2"),
        .init(modelId: "openrouter/moonshotai/kimi-k2.7-code", prov: "moonshot",   name: "Kimi K2.7 Code"),
        .init(modelId: "anthropic/claude-opus-4.6",            prov: "anthropic",  name: "Claude Opus 4.6"),
        .init(modelId: "openai/gpt-5.4",                       prov: "openai",     name: "GPT-5.4"),
        .init(modelId: "google/gemini-3-pro",                  prov: "google",     name: "Gemini 3 Pro"),
    ]

    static let thinkingLevels = ["minimal", "low", "medium", "high", "xhigh"]
    static func modelName(_ id: String) -> String { catalog.first { $0.modelId == id }?.name ?? id }

    static let slashCommands: [(String, String)] = [
        ("/model", "swap the active model"),
        ("/collab", "share session · link + QR"),
        ("/advisor", "toggle the reviewer model"),
        ("/review", "code review · P0–P3 verdict"),
        ("/commit", "atomic commits, validated"),
        ("/plan", "enter plan mode"),
        ("/debug", "debug · report · profile"),
        ("/login", "attach a coding plan"),
        ("/reload-plugins", "reload extensions"),
        ("/compact", "collapse the context"),
    ]

    // synthetic live activity appended to a running session
    static let liveStream: [UITurn] = [
        tool("bash", "$ swift test", "reconnect-fuzz · 41 cases"),
        sys("compaction", "COMPACTING CONTEXT"),
        tool("lsp", "lsp · diagnostics", "0 errors · 0 warnings"),
        agent("Iteration clean — the socket re-seals under simulated packet loss."),
        sys("ttsr", "RULE INJECTED · no-force-unwrap"),
        tool("task", "task · subagent", "worktree 3/5 · sealed frames ok"),
        sys("retry", "RETRY · FALLBACK MODEL"),
        tool("bash", "$ swift test", "214 / 214 passed · 2.1s"),
    ]
}
