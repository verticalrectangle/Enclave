# enclave relay

A self-hosted sealed collab relay — your own `my.omp.sh`. It's a blind broker:
it forwards AES-GCM envelopes between an omp host (`/enclave` or `/collab`) and
the phone guests in a room, and never sees plaintext. This is the one component
that wants an always-reachable host; omp and the app both dial *out* to it.

## Why self-host

`my.omp.sh` is Can's public relay for omp's own users, with the usual public
caps (size/rate) and third-party fragility. Your own relay removes the
dependency and any limits. It can't read your traffic either — everything is
sealed end to end.

## Run (behind Caddy, as on the wickrunner box)

```
npm install
node relay.js            # listens on 127.0.0.1:8787
```

Caddy terminates TLS and proxies WebSockets to it, on a dedicated port so the
live site is untouched:

```
wickrunner.com:8443 {
    reverse_proxy 127.0.0.1:8787
}
```

Then a collab/enclave link points at `wss://wickrunner.com:8443/r/<roomId>.<key>`.
(Open TCP 8443 on the host / Hetzner firewall.)

## Contract

`GET /r/<roomId>?role=host|guest` upgrades to WebSocket.
- host binary frame `[4B peerId][sealed]`: peer 0 broadcasts, peer N targets.
- guest binary frame: first 4 bytes rewritten to the sender's peer id → host.
- TEXT to host: `{"t":"peer-joined"|"peer-left","peer":N}`.
- host disconnect: `{"t":"room-closed"}` to guests, close 4001.
- fatal closes: 4004 no room · 4009 host taken · 4029 room full.

Matches `Sources/EngineBridge.swift` and omp's `local-relay.ts`.
