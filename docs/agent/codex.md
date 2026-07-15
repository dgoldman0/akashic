# Native Codex Account Provider

Akashic's Codex provider is a native, account-backed provider for MegaPad/KDOS.
It does not run Codex App Server, Codex CLI, Python, Node, or a Linux companion,
and it does not require an OpenAI API key. The user signs in with a ChatGPT
account and any resulting access remains behind the provider-neutral `AAUTH`
port.

The direct ChatGPT backend behavior is source-compatible rather than a
documented public integration contract. The implementation and deterministic
fixtures are pinned to official `openai/codex` commit
`5c19155cbd93bfa099016e7487259f61669823ff` from 2026-07-11. A staged live test
is required before treating a particular service behavior as compatible.

## Modules

```text
akashic/agent/providers/codex/config.f
akashic/agent/providers/codex/auth.f
akashic/agent/providers/codex/model-catalog.f
akashic/agent/providers/codex/provider.f
akashic/agent/providers/codex/source.f
akashic/agent/providers/codex/trust.f
```

`source.f` owns the complete provider construction environment: OAuth state,
separate KDOS TLS ports for authentication and model traffic, the bounded model
catalog, shared Responses configuration, and provider lifetime. TLS trust is a
separate boot contribution; constructing or freeing a source does not mutate
machine trust. Neither module contains a TUI or emulator service.

```forth
REQUIRE agent/providers/codex/source.f
REQUIRE agent/providers/codex/trust.f

: USE-CODEX  ( -- )
    CODEX-TRUST-REGISTER MTRUST-S-OK <>
    ABORT" Codex trust registration failed"
    CODEX-SOURCE-NEW
    0<> ABORT" Codex source allocation failed"
    DESK-AGENT-SOURCE! ;
```

## Account Flow

Agent's F9 account panel starts the native device flow. It displays
`https://auth.openai.com/codex/device` and a one-time code, polls without
blocking the TUI, shows account and plan metadata, and supports cancellation
and sign-out. The code is completed in any external browser; MegaPad does not
need a browser or receive browser cookies.

The auth owner handles PKCE exchange, bounded JWT claim extraction, expiry,
refresh-token rotation, one-shot unauthorized recovery, cancellation, logout,
and zeroization. Tokens remain memory-only until a generic sealed secret store
and root-key lifecycle pass review.

Device authorization polling reuses one authenticated HTTP/1.1 connection.
The buffered client preserves the transport after a complete response unless
the server requests `Connection: close`; a closed transport is reopened on the
next bounded poll. This avoids repeating native TLS setup for every pending
response without moving connection ownership out of the auth provider.

## Model Discovery

After authentication, the source requests the bounded Codex catalog through a
separate authenticated transport. The catalog implementation:

- Accepts at most 16 visible models, 8 reasoning levels per model, and 4 service
  tiers per model.
- Parses a bounded 512 KiB response and copies only model IDs, labels,
  descriptions, instructions, context limits, supported choices, and defaults.
- Filters non-list models and sorts listed models by provider priority.
- Applies the selected model's instructions, reasoning summary, service tier,
  verbosity, and ordinary or Responses Lite request mode to shared Responses
  configuration.
- Refreshes access and replays one catalog request after a 401; a repeated 401
  is terminal.

F8 opens the provider-neutral run-settings panel. Arrow keys select model,
reasoning, speed, and verbosity; `R` refreshes the catalog. The runtime rejects
selection changes while a run or approval review is active.

## Request Behavior

Codex reuses Akashic's native Responses engine. Account-backed requests add the
ChatGPT account header and honest Akashic originator/session metadata. The
selected catalog entry controls model instructions and whether the body uses
the exact Responses Lite projection. Tool calls still pass through Desk's Tool
Gateway, policy, approval, and applet-owned capability handlers.

## Trust And Live Network

The Codex trust module contributes the official Google Trust Services WE1
certificate as two exact-host anchors for `auth.openai.com` and `chatgpt.com`.
The embedded record includes its retrieval source, SHA-256 fingerprint,
revision date, and 2029-02-20 expiry. It does not grant trust to `openai.com`,
`api.openai.com`, arbitrary subdomains, or unrelated Google-hosted services.

`CODEX-TRUST-REGISTER` registers that contribution with the
[machine trust registry](../net/tls-trust-registry.md). Desk freezes all
registered contributions once before exposing external I/O. Standalone live
profiles perform the same register-then-freeze sequence explicitly; the Codex
source never installs or replaces a machine bundle itself.

This is a reviewed bootstrap profile, not a general WebPKI or unattended trust
update system. Intermediate/algorithm rotation requires a reviewed release;
signed updates and rollback protection remain release work. MegaPad permits an
unusable non-leaf certificate to be ignored only after its TLS entry bounds are
validated. The leaf must parse, and every certificate required to reach the
explicit anchor must remain supported and valid.

`codex-live-tls` is an opt-in credential-free TAP profile that authenticates
both hosts without sending HTTP, a device code, a token, or an API key.
`codex-live-auth` performs the native device-code request and continues polling;
`desktop-codex-live` is the TAP-configured watchable Desk environment. All live
profiles require an explicitly supplied `--nic-tap`; normal profiles attach no
real network.

The KDOS transport uses MegaPad's standard public ClientHello profile:
TLS 1.3 AES-128-GCM/SHA-256, X25519, HTTP/1.1 ALPN, and the one signature
scheme the native certificate path fully verifies. MegaPad's private hybrid
ML-KEM profile is never offered to these hosts. Failed opens preserve both the
provider-neutral transport error and the native TLS phase code for diagnosis.

## Verification

All normal profiles are native and offline:

- `codex-auth` covers device authorization, exchange, claims, refresh,
  cancellation, logout, zeroization, and stack balance.
- `codex-catalog` covers request headers, bounded parse/filter/sort, all run
  settings, ordinary and Lite projection, malformed recovery, and exact
  one-shot 401 retry.
- `codex-source` covers complete source/provider/catalog ownership and cleanup,
  proves source construction has no trust side effect, and verifies both exact
  Codex scopes without parent/suffix expansion after composition.
- `agent-device-ui` covers the full account/settings interaction using the
  reusable native source under `agent/providers/devtools/`.
- `desktop-codex` boots all applets with the real Codex source in signed-out
  production shape.

Agent/Desk hardening also has an offline acceptance gate. A change is not
complete merely because a provider can return text:

- `agent` verifies that offline, scripted, and remote provider provenance is
  explicit metadata rather than an inference from provider IDs.
- `agent-applet-capabilities` verifies the bounded, idempotent observation
  descriptors exported by Pad and File Explorer, including exact IDs, effects,
  target requirements, result schemas, and size limits.
- `agent-access` freezes the three Desk access-preset budgets and effects, then
  proves that an exact target pin wins when a foreign instance registers the
  same operation ID first.
- `agent-security` exercises reviewed-action audit envelopes, recursively typed
  canonical operand fingerprints, same-payload type mutation before and after
  approval, durable approval failure, queued and approval-state teardown,
  cancellation races, event capacity, and idle provider failures.
- `agent-layout-ui` loads a durable pathological transcript and requires hard
  newlines, long soft wrapping, wide Unicode, visual-row scrolling, bottom
  anchoring, and resize reflow without dropped text.
- `agent-ui` requires unmistakable demo/provider/access identity, an honest
  empty-send error, provider-review details, denial, cancellation, recovery,
  and transcript preservation across resize.
- `desktop-agent-hardening` drives Assist, Read only, and Chat only through the
  visible Access menu; validates each run's exact frozen operation set, flags,
  effects, and budgets; requires bounded multi-turn history made solely of
  same-run user/assistant pairs, structured local review details, approved and
  denied writes, rejection of capabilities outside the facet, ordinary chat
  with an empty tool facet, and conversation continuity after the Agent lens is
  closed and relaunched.
- `agent-device-ui` requires the selected model and reasoning choice to remain
  visible after the settings panel closes. `agent-persistence` retains the
  interrupted-run/reopen gate, and `openai-provider` exercises remote-provider
  provenance plus transport, tool, retry, and cancellation behavior.

These deterministic profiles must pass before a live run is useful evidence.
They deliberately use no network or account credential and do not substitute
for the live service gate below.

Live TAP runs have authenticated both source-pinned hosts and issued a real
device code from the native guest. During the first watched browser completion,
Desk stopped polling because MegaPad's 64-bit `MS@` reconstruction wrapped at
65.536 seconds. The BIOS fix and byte-complete clock regressions are present;
that interrupted run did not establish a guest token or account state.

The remaining live gate starts by repeating the watched login with the corrected
clock. It then requires account/plan and live catalog verification, a text turn,
one applet read, one reviewed persistent write, cancellation, logout, and
capture redaction. Failure must remain explicit; there is no API-key fallback.
