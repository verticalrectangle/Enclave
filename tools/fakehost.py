#!/usr/bin/env python3
"""fakehost — a controllable fake omp collab host + relay for testing Enclave.

Runs a WebSocket relay on localhost that speaks the Enclave collab wire protocol
(proto 3): 4-byte big-endian peer_id prefix + AES-256-GCM sealed JSON frames. It
accepts a guest's `hello`, then drives a scripted *scenario* of host frames so you
can exercise every app state (connecting / waiting / live / streaming / ended)
without a real coding agent.

WHY: the iOS guest has two paths that can strand forever if a host never answers —
the background watcher (Sessions list) and the active editor client. This host lets
you reproduce each one deterministically: a no-welcome host, a welcoming host, a
host mid-streaming-turn, a host that hangs up, etc.

DEPENDENCIES:  websockets>=13  cryptography
               (websockets 16 API: `handle(websocket)`, `process_request(conn, req)`)

USAGE (humans):
  # /collab — plain sessions, no enclave-caps
  ./tools/fakehost.py collab-chat        # welcome + streaming turn
  ./tools/fakehost.py collab-retry       # retry/fallback activity
  ./tools/fakehost.py collab-compaction  # compaction activity + entry
  ./tools/fakehost.py collab-notice      # notice chips (info/warning/error)
  ./tools/fakehost.py collab-goal        # goal banner
  ./tools/fakehost.py collab-tool        # tool execution card
  ./tools/fakehost.py collab-system-notice  # system-notice card

  # /enclave — sends enclave-caps, enables enhanced UI
  ./tools/fakehost.py enclave-caps       # welcome + caps, idle
  ./tools/fakehost.py enclave-ask        # ui-request select card
  ./tools/fakehost.py enclave-plan       # plan mode + editor approval
  ./tools/fakehost.py enclave-tool       # tool card + image fetch
  ./tools/fakehost.py enclave-vision     # prompt with images (placeholder)
  ./tools/fakehost.py enclave-slash      # slash command palette

  # generic (no prefix — basic connectivity)
  ./tools/fakehost.py no-welcome         # accept socket, never welcome
  ./tools/fakehost.py welcome            # welcome + empty snapshot
  ./tools/fakehost.py idle               # welcome, then silence
  ./tools/fakehost.py bye                # welcome, then hang up
  ./tools/fakehost.py error              # never welcome, send error
  ./tools/fakehost.py self-test          # in-process handshake check

  options: --port 8787 --host 127.0.0.1 --title "Fake Host" --turn-delay 0.5 --json

USAGE (agents): pass --json; the ONLY line on stdout is a parseable status object:
    {"ok": true, "link": "ws://127.0.0.1:8787/r/<room>.<key>", "scenario": "...",
     "host": "127.0.0.1", "port": 8787, "pid": 12345}
  All human logs go to stderr, so stdout stays clean to parse.

SCENARIO PREFIXES:
  • `collab-*` scenarios welcome the guest but never send `enclave-caps`; they
    exercise the surfaces the plain /collab transcript renders.
  • `enclave-*` scenarios send `enclave-caps` immediately after the welcome,
    flipping the guest into enhanced mode (toolbar model/thinking controls,
    slash palette, AskCard editor, etc.).

NOTE: `enclave-vision` is a placeholder — it sends a text-only assistant reply
and a "READING YOUR IMAGE VIA VISION…" notice instead of a real image analysis
response. It still exercises the prompt-with-images path and the vision status UI.

NOTE: the iOS app connects to localhost, so run this ON THE MACHINE HOSTING THE
SIMULATOR/DEVICE (the Mac), e.g. after `./build-mac.sh`. To point the app at it,
seed the link as the sole saved session (pass --json to read it machine-readably).
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import secrets
import struct
import sys
import time
from typing import Any, Awaitable, Callable
try:
    import websockets
    from websockets.http11 import Response
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    _HAS_DEPS = True
except ImportError:  # pragma: no cover - help/list still work without runtime deps
    _HAS_DEPS = False
PROTO = 3
DEFAULT_PORT = 8787
DEFAULT_HOST = "127.0.0.1"
DEFAULT_TITLE = "Fake Host"


# ── wire codec ────────────────────────────────────────────────────────────────
def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


class Codec:
    """AES-256-GCM sealed JSON, matching @oh-my-pi/collab codec.ts exactly."""

    def __init__(self, key: bytes):
        self.aes = AESGCM(key)

    @classmethod
    def from_b64url(cls, b64: str) -> "Codec":
        pad = "=" * (-len(b64) % 4)
        return cls(base64.urlsafe_b64decode(b64 + pad))

    def seal(self, frame: dict[str, Any]) -> bytes:
        plain = json.dumps(frame).encode()
        nonce = secrets.token_bytes(12)
        return nonce + self.aes.encrypt(nonce, plain, None)

    def open(self, data: bytes) -> dict[str, Any] | None:
        if len(data) <= 12:
            return None
        nonce, ct = data[:12], data[12:]
        try:
            return json.loads(self.aes.decrypt(nonce, ct, None))
        except Exception:
            return None


def framed(peer_id: int, payload: bytes) -> bytes:
    """4-byte big-endian peer_id prefix + payload. Host→guest broadcast = peer 0."""
    return struct.pack(">I", peer_id) + payload


# ── host frames ───────────────────────────────────────────────────────────────
def welcome_frame(title: str, entry_count: int = 0) -> dict[str, Any]:
    return {
        "t": "welcome",
        "proto": PROTO,
        "header": {
            "type": "session",
            "id": "fake-session",
            "title": title,
            "timestamp": str(int(time.time() * 1000)),
            "cwd": "/tmp",
        },
        "state": {
            "isStreaming": False,
            "queuedMessageCount": 0,
            "cwd": "/tmp",
            "participants": [{"name": "fakehost", "role": "host"}],
        },
        "agents": [],
        "entryCount": entry_count,
    }


def snapshot_frame(entries: list[dict] | None = None, final: bool = True) -> dict[str, Any]:
    return {"t": "snapshot-chunk", "entries": entries or [], "final": final}


def event(evt: dict[str, Any]) -> dict[str, Any]:
    return {"t": "event", "event": evt}


def state_frame(**fields: Any) -> dict[str, Any]:
    return {"t": "state", "state": fields}


def bye_frame(reason: str = "host ended") -> dict[str, Any]:
    return {"t": "bye", "reason": reason}


def error_frame(message: str = "host error") -> dict[str, Any]:
    return {"t": "error", "message": message}


def assistant_payload(thinking: str, text: str) -> dict[str, Any]:
    """The `message` body for a message_start/update/end event (thinking + text)."""
    return {
        "role": "assistant",
        "content": [
            {"type": "thinking", "thinking": thinking},
            {"type": "text", "text": text},
        ],
        "model": "fakehost-pro",
        "usage": {"input": 100, "output": 0, "totalTokens": 100,
                  "cost": {"total": 0.0}},
        "stopReason": "stop",
        "timestamp": int(time.time() * 1000),
    }

def entry_frame(entry: dict[str, Any]) -> dict[str, Any]:
    return {"t": "entry", "entry": entry}


def user_prompt_entry(text: str, eid: str = "prompt-1") -> dict[str, Any]:
    # EngineBridge projects a custom_message/collab-prompt entry as the user's turn.
    return {"type": "custom_message", "customType": "collab-prompt", "id": eid,
            "content": [{"type": "text", "text": text}]}


def assistant_entry(thinking: str, text: str, eid: str = "msg-1") -> dict[str, Any]:
    # A finalized assistant message the transcript keeps after the stream ghost clears.
    return {"type": "message", "id": eid, "message": assistant_payload(thinking, text)}


def system_notice_entry(content_text: str, eid: str = "sys-notice-1") -> dict[str, Any]:
    """Harness system-notice custom_message entry — rendered as a SystemNoticeCard."""
    return {
        "type": "custom_message",
        "customType": "system-notice",
        "display": True,
        "id": eid,
        "content": [{"type": "text", "text": content_text}],
    }


# ── enclave / enhanced host frames ───────────────────────────────────────────
def caps_frame(
    vision: bool = False,
    native_vision: bool = True,
    vision_model_available: bool = False,
    commands: list[dict[str, Any]] | None = None,
    models: list[dict[str, Any]] | None = None,
    thinking: list[str] | None = None,
    current_thinking: str = "",
    version: int = 1,
) -> dict[str, Any]:
    return {
        "t": "enclave-caps",
        "version": version,
        "vision": vision,
        "nativeVision": native_vision,
        "visionModelAvailable": vision_model_available,
        "commands": commands or [],
        "models": models or [],
        "thinking": thinking or [],
        "current": {"thinking": current_thinking},
    }


def enclave_result(
    req_id: int,
    ok: bool,
    message: str | None = None,
    data: str | None = None,
    mime_type: str | None = None,
) -> dict[str, Any]:
    frame: dict[str, Any] = {"t": "enclave-result", "reqId": req_id, "ok": ok}
    if message is not None:
        frame["message"] = message
    if data is not None:
        frame["data"] = data
    if mime_type is not None:
        frame["mimeType"] = mime_type
    return frame


def ui_request_frame(
    req_id: int,
    kind: str,
    title: str,
    help_text: str,
    options: list[Any] | None = None,
    selection_marker: str = "radio",
    initial_index: int | None = None,
    checked_indices: list[int] | None = None,
    prefill: str | None = None,
) -> dict[str, Any]:
    request: dict[str, Any] = {
        "reqId": req_id,
        "kind": kind,
        "title": title,
        "helpText": help_text,
    }
    if options is not None:
        request["options"] = options
    if selection_marker is not None:
        request["selectionMarker"] = selection_marker
    if initial_index is not None:
        request["initialIndex"] = initial_index
    if checked_indices is not None:
        request["checkedIndices"] = checked_indices
    if prefill is not None:
        request["prefill"] = prefill
    return {"t": "ui-request", "request": request}


def ui_request_end_frame(req_id: int) -> dict[str, Any]:
    return {"t": "ui-request-end", "reqId": req_id}


def tool_event(kind: str, tool_call_id: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
    """Host-side tool execution event.  `kind` must be one of the
    `tool_execution_*` or `notice` types the guest renders."""
    evt: dict[str, Any] = {"type": kind, "toolCallId": tool_call_id}
    if data is not None:
        evt.update(data)
    return {"t": "event", "event": evt}


def notice_frame(level: str, message: str) -> dict[str, Any]:
    return event({"type": "notice", "level": level, "message": message})


def goal_frame(
    objective: str,
    status: str = "active",
    tokens_used: int = 0,
    token_budget: int | None = None,
) -> dict[str, Any]:
    goal: dict[str, Any] = {
        "objective": objective,
        "status": status,
        "tokensUsed": tokens_used,
    }
    if token_budget is not None:
        goal["tokenBudget"] = token_budget
    return event({"type": "goal_updated", "goal": goal})


def retry_event(kind: str, **kwargs: Any) -> dict[str, Any]:
    """Retry / compaction activity events."""
    return event({"type": kind, **kwargs})


def thinking_level_changed_frame(level: str) -> dict[str, Any]:
    return event({"type": "thinking_level_changed", "thinkingLevel": level})


# ── entry helpers (reusing entry_frame) ───────────────────────────────────────
def mode_change_entry(mode: str, eid: str = "mode-1") -> dict[str, Any]:
    return {"type": "mode_change", "mode": mode, "id": eid}


def thinking_level_change_entry(level: str, eid: str = "think-1") -> dict[str, Any]:
    return {"type": "thinking_level_change", "thinkingLevel": level, "id": eid}


def model_change_entry(model: str, eid: str = "model-1") -> dict[str, Any]:
    return {"type": "model_change", "model": model, "id": eid}


def compaction_entry(summary: str, eid: str = "compact-1") -> dict[str, Any]:
    return {"type": "compaction", "shortSummary": summary, "id": eid}


def tool_result_entry(
    tool_call_id: str,
    tool_name: str,
    content: list[dict[str, Any]],
    is_error: bool = False,
    details: dict[str, Any] | None = None,
    eid: str = "tool-1",
) -> dict[str, Any]:
    msg: dict[str, Any] = {
        "role": "toolResult",
        "toolName": tool_name,
        "toolCallId": tool_call_id,
        "content": content,
        "isError": is_error,
    }
    if details is not None:
        msg["details"] = details
    return {"type": "message", "id": eid, "message": msg}


# ── scenarios ─────────────────────────────────────────────────────────────────
# A scenario is (welcomes: bool, driver: async (send, log, delay) -> None).
# `send` frames + broadcasts to the guest. `welcomes=False` skips the welcome so the
# guest never leaves the waiting/connecting state.

ScenarioDriver = Callable[["Sender", "Logger", float, "asyncio.Queue"], Awaitable[None]]


class Sender:
    """Wraps a websocket + codec so scenarios just call send(frame)."""

    def __init__(self, ws, codec: Codec):
        self.ws = ws
        self.codec = codec

    async def send(self, frame: dict[str, Any]) -> None:
        await self.ws.send(framed(0, self.codec.seal(frame)))

    async def __call__(self, frame: dict[str, Any]) -> None:
        await self.send(frame)


Logger = Callable[[str], None]


async def _no_welcome(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("accepted hello; never sending welcome")
    await asyncio.Future()  # keep the connection open without welcoming


async def _idle(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; sitting idle (READY)")


async def _bye(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    await asyncio.sleep(delay)
    await send(bye_frame("fakehost hung up"))
    log("sent bye")


# A tiny transparent 1x1 PNG used as a placeholder image fetch result.
_TINY_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="


async def _error(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    await asyncio.sleep(delay)
    await send(error_frame("fakehost refused the session"))
    log("sent error")


# ── /collab scenarios (no enclave-caps) ───────────────────────────────────────
async def _collab_chat(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    """A realistic reasoning turn: think → stream text → finalize."""
    # Seed the user's prompt as an entry so the transcript has context.
    await send(entry_frame(user_prompt_entry("What's the answer to everything?")))
    await asyncio.sleep(delay)
    await send(event({"type": "agent_start"}))
    await send(state_frame(isStreaming=True, queuedMessageCount=0))
    log("agent_start")
    await asyncio.sleep(delay * 2)

    await send(event({"type": "message_start",
                      "message": assistant_payload("Let me think about this step by step.\n\nAnalyzing the problem…", "")}))
    log("message_start (thinking)")
    await asyncio.sleep(delay * 2)

    await send(event({"type": "message_update",
                      "message": assistant_payload(
                          "Let me think about this step by step.\n\n"
                          "First, decompose into subproblems.\nThe key insight is approach A.",
                          "Based on my analysis")}))
    log("message_update (thinking + partial text)")
    await asyncio.sleep(delay * 2)

    await send(event({"type": "message_end",
                      "message": assistant_payload(
                          "Let me think about this step by step.\n\n"
                          "First, decompose into subproblems.\n"
                          "After careful analysis, approach A wins on X, Y, Z.",
                          "Based on my analysis, here's the solution:\n\nThe answer is **42**.")}))
    log("message_end (finalized)")
    # Persist the finalized assistant reply as an entry (the stream ghost clears on agent_end).
    await send(entry_frame(assistant_entry(
        "Let me think about this step by step.\n\n"
        "First, decompose into subproblems.\n"
        "After careful analysis, approach A wins on X, Y, Z.",
        "Based on my analysis, here's the solution:\n\nThe answer is **42**.")))
    await send(event({"type": "agent_end"}))
    await send(state_frame(isStreaming=False, queuedMessageCount=0))
    log("agent_end — turn complete")


async def _collab_retry(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; simulating retry/fallback")
    await send(retry_event("auto_retry_start", attempt=1, maxAttempts=3))
    await asyncio.sleep(delay)
    await send(retry_event("retry_fallback_applied", to="backup-model"))
    await asyncio.sleep(delay)
    await send(retry_event("retry_fallback_succeeded"))
    await send(retry_event("auto_retry_end", success=True))
    await send(entry_frame(assistant_entry(
        "Fallback model recovered the answer.",
        "The retry succeeded — answer is **42**.")))
    await send(state_frame(isStreaming=False, queuedMessageCount=0))


async def _collab_compaction(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; simulating compaction")
    await send(retry_event("auto_compaction_start"))
    await asyncio.sleep(delay)
    await send(retry_event("auto_compaction_end"))
    await send(entry_frame(compaction_entry("Kept the key decisions from the last 20 turns.")))


async def _collab_notice(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; sending notices")
    await send(notice_frame("info", "This is an informational notice."))
    await asyncio.sleep(delay)
    await send(notice_frame("warning", "This is a warning notice."))
    await asyncio.sleep(delay)
    await send(notice_frame("error", "This is an error notice."))


async def _collab_goal(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; sending goal")
    await send(goal_frame(
        objective="Refactor the networking layer to use async/await",
        status="active",
        tokens_used=12500,
        token_budget=50000))


async def _collab_tool(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; simulating tool use")
    await send(entry_frame(user_prompt_entry("Run a quick check.")))
    await asyncio.sleep(delay)
    tool_call_id = "tool-call-1"
    await send(tool_event("tool_execution_start", tool_call_id, {"name": "run_command", "arguments": {"command": "uname -a"}}))
    await asyncio.sleep(delay)
    await send(tool_event("tool_execution_update", tool_call_id, {"name": "run_command", "content": [{"type": "text", "text": "Linux fakehost 5.0 x86_64"}]}))
    await asyncio.sleep(delay)
    await send(tool_event("tool_execution_end", tool_call_id, {"name": "run_command"}))
    await send(entry_frame(tool_result_entry(
        tool_call_id=tool_call_id,
        tool_name="run_command",
        content=[{"type": "text", "text": "Linux fakehost 5.0 x86_64"}],
        details={"command": "uname -a"})))


async def _collab_system_notice(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; sending system-notice entry")
    output_json = json.dumps({
        "summary": "Investigated layout of Sources/RootView.swift and Sources/SessionsView.swift."
    })
    notice = (
        "<system-notice>\n"
        "Background job RootSessionsLayout has completed. Resume your work using the result below.\n"
        '<task-result id="RootSessionsLayout" agent="task" status="completed" duration="1m">\n'
        '<meta lines="3" size="418B" />\n'
        "<output>\n"
        f"{output_json}\n"
        "</output>\n"
        "</task-result>\n"
        "RootSessionsLayout is now idle — message it via `irc` to follow up; transcript at history://RootSessionsLayout\n"
        "</system-notice>"
    )
    await send(entry_frame(system_notice_entry(notice)))


async def _syntax_highlight(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    """Exercise fenced code blocks: swift, diff, inline backticks, and tool +/- lines."""
    await send(entry_frame(user_prompt_entry("Show me syntax highlighting.")))
    await asyncio.sleep(delay)

    swift_block = """Here is a Swift block:
```swift
import SwiftUI

struct CounterView: View {
    @State var count = 0
    let title = "Hello"

    var body: some View {
        // button increments the count
        Button(title) {
            count += 1
        }
        .font(.title)
    }
}
```
And a diff:
```diff
+ added line
- removed line
 context line
@@ -1,2 +1,2 @@
```
Inline `backtick code` should keep its tint."""

    await send(entry_frame(assistant_entry("", swift_block, eid="msg-syntax")))

    # Tool card with +/- lines.
    await send(entry_frame(user_prompt_entry("Apply this patch.")))
    await asyncio.sleep(delay)
    tool_call_id = "patch-tool-1"
    await send(tool_event("tool_execution_start", tool_call_id, {"name": "apply_patch"}))
    await send(tool_event("tool_execution_update", tool_call_id, {"name": "apply_patch", "content": [{"type": "text", "text": "+ added line\n- removed line"}]}))
    await send(tool_event("tool_execution_end", tool_call_id, {"name": "apply_patch"}))
    await send(entry_frame(tool_result_entry(
        tool_call_id=tool_call_id,
        tool_name="apply_patch",
        content=[{"type": "text", "text": "+ added line\n- removed line\ncontext line"}],
        details={"command": "apply patch"})))
    log("sent syntax-highlight exercise")


# ── /enclave scenarios (send enclave-caps after welcome) ──────────────────────
async def _enclave_caps(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; sending enclave-caps")
    await send(caps_frame(
        vision=True,
        native_vision=False,
        vision_model_available=True,
        commands=[{"name": "explain", "summary": "Explain the selected code"},
                  {"name": "fix", "summary": "Fix the issue"}],
        models=[{"id": "pro", "name": "Pro", "vision": True},
                {"id": "fast", "name": "Fast", "vision": False}],
        thinking=["light", "medium", "deep"],
        current_thinking="medium"))
    await send(state_frame(model={"name": "Pro"}, thinkingLevel="medium"))
    log("sent enclave-caps; idling")
    await asyncio.Future()  # keep session alive for manual inspection


async def _enclave_ask(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; sending enclave-caps + ask")
    await send(caps_frame(
        vision=True,
        native_vision=False,
        vision_model_available=True,
        commands=[{"name": "explain", "summary": "Explain the selected code"}],
        models=[{"id": "pro", "name": "Pro", "vision": True}],
        thinking=["light", "medium", "deep"],
        current_thinking="medium"))
    await send(state_frame(model={"name": "Pro"}, thinkingLevel="medium"))
    await asyncio.sleep(delay)
    req_id = 1
    await send(ui_request_frame(
        req_id=req_id,
        kind="select",
        title="Choose a thinking level",
        help_text="Pick how deeply the model should reason for this session.",
        options=["Light", "Medium", "Deep"],
        selection_marker="radio",
        initial_index=1))
    log("sent ui-request; waiting for ui-response")
    response = await q.get()
    log(f"got ui-response: {response.get('value')!r}")
    await send(ui_request_end_frame(req_id))
    await send(thinking_level_changed_frame(response.get("value", "medium").lower()))
    await send(state_frame(thinkingLevel=response.get("value", "medium").lower()))


async def _enclave_plan(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; sending enclave-caps + plan approval")
    await send(caps_frame(
        vision=False,
        native_vision=True,
        vision_model_available=False,
        commands=[],
        models=[{"id": "pro", "name": "Pro", "vision": False}],
        thinking=["light", "medium", "deep"],
        current_thinking="deep"))
    await send(state_frame(model={"name": "Pro"}, thinkingLevel="deep"))
    await send(entry_frame(mode_change_entry("plan", eid="mode-plan")))
    await asyncio.sleep(delay)
    req_id = 2
    await send(ui_request_frame(
        req_id=req_id,
        kind="editor",
        title="Plan approval",
        help_text="Review the proposed plan. Edit it if needed, then approve.",
        prefill="1. Audit the current networking calls\n"
                "2. Introduce async/await wrappers\n"
                "3. Add cancellation tests\n"
                "4. Migrate the remaining callers"))
    log("sent plan editor; waiting for ui-response")
    response = await q.get()
    log(f"got plan approval: {response.get('value')!r}")
    await send(ui_request_end_frame(req_id))
    await send(entry_frame(mode_change_entry("none", eid="mode-none")))


async def _enclave_tool(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; simulating enclave tool use")
    await send(caps_frame(
        vision=True,
        native_vision=False,
        vision_model_available=True,
        commands=[],
        models=[{"id": "pro", "name": "Pro", "vision": True}],
        thinking=["light", "medium", "deep"],
        current_thinking="medium"))
    await send(state_frame(model={"name": "Pro"}, thinkingLevel="medium"))
    await send(entry_frame(user_prompt_entry("Inspect this image.")))
    await asyncio.sleep(delay)
    tool_call_id = "img-tool-1"
    image_path = "screenshot.png"
    await send(tool_event("tool_execution_start", tool_call_id, {"name": "inspect_image", "arguments": {"path": image_path}}))
    await asyncio.sleep(delay)
    await send(tool_event("tool_execution_update", tool_call_id, {"name": "inspect_image", "content": [{"type": "text", "text": "Analyzing image…"}]}))
    await asyncio.sleep(delay)
    await send(tool_event("tool_execution_end", tool_call_id, {"name": "inspect_image"}))
    await send(entry_frame(tool_result_entry(
        tool_call_id=tool_call_id,
        tool_name="inspect_image",
        content=[{"type": "text", "text": "A screenshot of the Enclave app."}],
        details={"imagePath": image_path, "mimeType": "image/png"})))
    log("sent tool result; waiting for fetch-image")
    while True:
        cmd = await q.get()
        if cmd.get("t") == "enclave-cmd" and cmd.get("method") == "fetch-image":
            break
    req_id = cmd.get("reqId", 10)
    log(f"got fetch-image reqId={req_id}; returning placeholder PNG")
    await send(enclave_result(req_id, ok=True, data=_TINY_PNG, mime_type="image/png"))
    await send(entry_frame(assistant_entry(
        "I inspected the image.",
        "The image shows the Enclave app running in the simulator.")))


async def _enclave_vision(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; sending vision caps; waiting for prompt with images")
    await send(caps_frame(
        vision=True,
        native_vision=False,
        vision_model_available=True,
        commands=[],
        models=[{"id": "pro", "name": "Pro", "vision": True}],
        thinking=["light", "medium", "deep"],
        current_thinking="medium"))
    await send(state_frame(model={"name": "Pro"}, thinkingLevel="medium"))
    while True:
        frame = await q.get()
        if frame.get("t") == "prompt":
            images = frame.get("images", [])
            if images:
                break
    log(f"got prompt with {len(images)} image(s)")
    await send(notice_frame("info", "READING YOUR IMAGE VIA VISION…"))
    await asyncio.sleep(delay)
    await send(entry_frame(assistant_entry(
        "I see a screenshot in the message.",
        "The image shows the Enclave app. Here is what I can tell you about it.")))


async def _enclave_slash(send: Sender, log: Logger, delay: float, q: asyncio.Queue) -> None:
    log("welcomed; sending slash command caps")
    await send(caps_frame(
        vision=False,
        native_vision=True,
        vision_model_available=False,
        commands=[{"name": "explain", "summary": "Explain the selected code"},
                  {"name": "fix", "summary": "Fix the issue"}],
        models=[{"id": "pro", "name": "Pro", "vision": False}],
        thinking=["light", "medium", "deep"],
        current_thinking="medium"))
    await send(state_frame(model={"name": "Pro"}, thinkingLevel="medium"))
    while True:
        frame = await q.get()
        if frame.get("t") == "enclave-cmd" and frame.get("method") == "slash":
            break
    req_id = frame.get("reqId", 3)
    params = frame.get("params", {})
    command = params.get("name", "unknown")
    args = params.get("args", "")
    log(f"got slash command: /{command} {args}")
    await send(enclave_result(req_id, ok=True))
    await send(notice_frame("info", f"Ran /{command} successfully"))


SCENARIOS: dict[str, tuple[str, bool, ScenarioDriver]] = {
    # name: (description, welcomes?, driver)
    "no-welcome":    ("accept socket, never welcome — exercises the welcome timeout", False, _no_welcome),
    "welcome":       ("welcome + empty snapshot — editor loads and stays (negative control)", True, _idle),
    "idle":          ("welcome + snapshot, then silence — READY state", True, _idle),
    "bye":           ("welcome, then host hangs up — session ends → OFFLINE", True, _bye),
    "error":         ("never welcome; send an error frame", False, _error),
    "collab-chat":   ("/collab: welcome + a simulated reasoning turn", True, _collab_chat),
    "collab-retry":  ("/collab: retry/fallback activity events", True, _collab_retry),
    "collab-compaction": ("/collab: compaction activity + entry", True, _collab_compaction),
    "collab-notice": ("/collab: notice chips", True, _collab_notice),
    "collab-goal":   ("/collab: goal banner", True, _collab_goal),
    "collab-tool":   ("/collab: tool execution card", True, _collab_tool),
    "collab-system-notice": ("/collab: system-notice card (harness background-job)", True, _collab_system_notice),
    "syntax-highlight": ("/collab: fenced code blocks + diff + tool +/- coloring", True, _syntax_highlight),
    "enclave-caps":  ("/enclave: welcome + enclave-caps, then idle", True, _enclave_caps),
    "enclave-ask":   ("/enclave: ui-request select card", True, _enclave_ask),
    "enclave-plan":  ("/enclave: plan mode + editor approval", True, _enclave_plan),
    "enclave-tool":  ("/enclave: tool card + image fetch", True, _enclave_tool),
    "enclave-vision":("/enclave: prompt with images + vision notice", True, _enclave_vision),
    "enclave-slash": ("/enclave: slash command palette", True, _enclave_slash),
}


# ── server ────────────────────────────────────────────────────────────────────
class FakeHost:
    def __init__(self, scenario: str, title: str, delay: float, log: Logger):
        self.scenario = scenario
        self.title = title
        self.delay = delay
        self.log = log
        # one room/key per run; the codec is shared so any guest with the link can seal/open.
        self.key = secrets.token_bytes(32)
        self.room_id = secrets.token_hex(8)
        self.link = f"ws://{DEFAULT_HOST}:{DEFAULT_PORT}/r/{self.room_id}.{_b64url(self.key)}"
        self.codec = Codec(self.key)

    def with_endpoint(self, host: str, port: int) -> "FakeHost":
        self.link = f"ws://{host}:{port}/r/{self.room_id}.{_b64url(self.key)}"
        return self

    async def process_request(self, connection, request) -> Response | None:
        # Two kinds of request hit /r/<room>.<key>:
        #   • the app's liveness probe — a plain HTTP GET (no Upgrade header)
        #   • the guest's WebSocket upgrade — Upgrade: websocket
        # Answer the probe with {"live": true}, but return None for upgrades so the
        # 101 handshake proceeds (returning a Response here would abort it).
        is_upgrade = request.headers.get("Upgrade", "").lower() == "websocket"
        if not is_upgrade and request.path.split("?")[0].startswith("/r/"):
            return Response(
                200, "OK",
                websockets.Headers({"Content-Type": "application/json",
                                    "Access-Control-Allow-Origin": "*"}),
                json.dumps({"live": True}).encode(),
            )
        return None

    async def handle(self, websocket) -> None:
        path = websocket.request.path
        welcomes, driver = SCENARIOS[self.scenario][1], SCENARIOS[self.scenario][2]
        sender = Sender(websocket, self.codec)
        guest_queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self.log(f"guest connected ({path})")

        async def receive_loop() -> None:
            try:
                async for msg in websocket:
                    if isinstance(msg, str) or len(msg) <= 4:
                        continue
                    frame = self.codec.open(msg[4:])
                    if not frame:
                        self.log("bad seal from guest")
                        continue
                    t = frame.get("t")
                    self.log(f"guest → {t}")
                    await guest_queue.put(frame)
            except websockets.ConnectionClosed:
                pass

        async def run_driver() -> None:
            # Wait for hello; ignore any pre-hello frames.
            while True:
                frame = await guest_queue.get()
                guest_queue.task_done()
                if frame.get("t") == "hello":
                    break
            if welcomes:
                await sender.send(welcome_frame(self.title))
                await sender.send(snapshot_frame())
                self.log("→ welcome + snapshot")
            await driver(sender, self.log, self.delay, guest_queue)

        receive_task = asyncio.create_task(receive_loop())
        driver_task = asyncio.create_task(run_driver())
        try:
            await receive_task
        except websockets.ConnectionClosed:
            pass
        finally:
            driver_task.cancel()
            try:
                await driver_task
            except asyncio.CancelledError:
                pass
            self.log("guest disconnected")

    async def serve(self, host: str, port: int) -> None:
        async with websockets.serve(self.handle, host, port, process_request=self.process_request):
            await asyncio.Future()  # run forever


# ── self-test (no simulator required) ─────────────────────────────────────────
async def _self_test(scenario: str, host: str) -> dict[str, Any]:
    """Start the host on an ephemeral port, connect a client, verify the frames."""
    port = 0  # ephemeral
    results: dict[str, Any] = {"scenario": scenario}

    def quiet(_: str) -> None:
        pass

    fh = FakeHost(scenario, DEFAULT_TITLE, 0.05, quiet)
    server = await websockets.serve(fh.handle, host, port, process_request=fh.process_request)
    # resolve the actual ephemeral port the server picked
    socks = server.sockets
    actual_port = socks[0].getsockname()[1] if socks else port
    fh.link = f"ws://{host}:{actual_port}/r/{fh.room_id}.{_b64url(fh.key)}"
    results["link"] = fh.link

    async def client() -> None:
        async with websockets.connect(fh.link) as ws:
            results["handshake"] = "ok"
            codec = fh.codec
            await ws.send(framed(0, codec.seal({"t": "hello", "proto": PROTO, "name": "self-test"})))
            welcomes = SCENARIOS[scenario][1]
            if not welcomes and scenario == "no-welcome":
                # expect no welcome within a short window
                try:
                    await asyncio.wait_for(ws.recv(), timeout=0.6)
                    results["welcome"] = "unexpected"
                except asyncio.TimeoutError:
                    results["welcome"] = "withheld-ok"
                return

            # drain frames the scenario emits; confirm a welcome arrives
            got_welcome = False
            got_caps = False
            ui_request_id: int | None = None
            got_ui_request_end = False
            deadline = asyncio.get_event_loop().time() + 4.0
            while asyncio.get_event_loop().time() < deadline:
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=1.0)
                except asyncio.TimeoutError:
                    break
                if not isinstance(raw, bytes) or len(raw) <= 4:
                    continue
                f = codec.open(raw[4:])
                if not f:
                    continue
                t = f.get("t")
                if t == "welcome":
                    got_welcome = True
                elif t == "enclave-caps":
                    got_caps = True
                elif t == "ui-request":
                    ui_request_id = f.get("request", {}).get("reqId")
                elif t == "ui-request-end":
                    got_ui_request_end = True

            results["welcome"] = "ok" if got_welcome else "missing"
            if scenario == "enclave-caps":
                results["enclave-caps"] = "ok" if got_caps else "missing"

            if scenario == "enclave-ask" and ui_request_id is not None:
                await ws.send(framed(0, codec.seal({"t": "ui-response", "reqId": ui_request_id, "value": "Medium"})))
                # drain a bit more for ui-request-end
                deadline = asyncio.get_event_loop().time() + 2.0
                while asyncio.get_event_loop().time() < deadline:
                    try:
                        raw = await asyncio.wait_for(ws.recv(), timeout=0.5)
                    except asyncio.TimeoutError:
                        break
                    if not isinstance(raw, bytes) or len(raw) <= 4:
                        continue
                    f = codec.open(raw[4:])
                    if f and f.get("t") == "ui-request-end":
                        got_ui_request_end = True

            if scenario == "enclave-ask":
                results["ui-request"] = "ok" if ui_request_id is not None else "missing"
                results["ui-request-end"] = "ok" if got_ui_request_end else "missing"

    try:
        await client()
    finally:
        server.close()
        await server.wait_closed()
    results["ok"] = results.get("handshake") == "ok"
    if scenario == "enclave-caps":
        results["ok"] = results["ok"] and results.get("enclave-caps") == "ok"
    if scenario == "enclave-ask":
        results["ok"] = results["ok"] and results.get("ui-request") == "ok" and results.get("ui-request-end") == "ok"
    return results


# ── CLI ───────────────────────────────────────────────────────────────────────
def _emit_json(obj: dict[str, Any]) -> None:
    print(json.dumps(obj), flush=True)


def _human_logger(line: str) -> None:
    print(f"  [host] {line}", file=sys.stderr, flush=True)


def _silent_logger(_: str) -> None:
    pass


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        prog="fakehost",
        description="A controllable fake omp collab host for testing Enclave.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="scenarios:\n" + "\n".join(f"  {n:<12} {d}" for n, (d, _, _) in SCENARIOS.items()),
    )
    p.add_argument("scenario", nargs="?", choices=list(SCENARIOS) + ["self-test"],
                   help="which host behavior to simulate")
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    p.add_argument("--host", default=DEFAULT_HOST)
    p.add_argument("--title", default=DEFAULT_TITLE, help="session title sent in the welcome frame")
    p.add_argument("--turn-delay", type=float, default=0.5, dest="delay",
                   help="seconds between streaming-turn frames")
    p.add_argument("--json", action="store_true",
                   help="emit a single parseable status object on stdout (for agents)")
    p.add_argument("--list", action="store_true", help="list scenarios and exit")
    args = p.parse_args(argv)

    if args.list or not args.scenario:
        for n, (d, _, _) in SCENARIOS.items():
            print(f"{n:<12} {d}")
        return 0
    if not _HAS_DEPS:
        print("error: websockets and cryptography are required to run the host.", file=sys.stderr)
        print("       pip install websockets cryptography", file=sys.stderr)
        return 1

    log = _silent_logger if args.json else _human_logger

    if args.scenario == "self-test":
        # verify: withheld welcome, delivered welcome, a frame-sending driver (bye),
        # enclave-caps broadcast, and the ui-request / ui-response round-trip.
        out = {}
        for sc in ("no-welcome", "welcome", "bye", "enclave-caps", "enclave-ask"):
            r = asyncio.run(_self_test(sc, args.host))
            out[sc] = r
        ok = all(r["ok"] for r in out.values())
        if args.json:
            _emit_json({"ok": ok, "self-test": out})
        else:
            print("self-test:", "PASS" if ok else "FAIL")
            for sc, r in out.items():
                extras = ""
                if "enclave-caps" in r:
                    extras += f" caps={r['enclave-caps']}"
                if "ui-request" in r:
                    extras += f" ui-request={r['ui-request']} ui-request-end={r['ui-request-end']}"
                print(f"  {sc:<12} handshake={r.get('handshake')} welcome={r.get('welcome')}{extras}")
        return 0 if ok else 1

    desc = SCENARIOS[args.scenario][0]
    fh = FakeHost(args.scenario, args.title, args.delay, log).with_endpoint(args.host, args.port)

    if args.json:
        _emit_json({"ok": True, "link": fh.link, "scenario": args.scenario,
                    "host": args.host, "port": args.port, "pid": os.getpid()})
    else:
        print(f"fakehost · {args.scenario} — {desc}", file=sys.stderr)
        print(f"  link: {fh.link}", file=sys.stderr)
        print(f"  (Ctrl-C to stop)", file=sys.stderr)

    try:
        asyncio.run(fh.serve(args.host, args.port))
    except KeyboardInterrupt:
        if not args.json:
            print("\n  stopped.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
