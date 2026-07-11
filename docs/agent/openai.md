# Native OpenAI Responses Provider

The OpenAI provider is implemented entirely in native Akashic and MegaPad
services. It does not invoke Python, a host bridge, Codex CLI, or an emulator
service.

## Modules

```text
akashic/agent/providers/openai/config.f
akashic/agent/providers/openai/request-codec.f
akashic/agent/providers/openai/event-codec.f
akashic/agent/providers/openai/responses.f
akashic/agent/providers/openai/megapad.f
```

`responses.f` implements the provider-neutral `APROV` callbacks over an `NIO`
port. `megapad.f` is the physical-machine composition: one allocation embeds
an OpenAI configuration, a generic zeroizing credential container, and the
native MegaPad TLS adapter. It owns no Desk or TUI behavior.

```forth
REQUIRE agent/providers/openai/megapad.f

: USE-OPENAI  ( -- )
    OPENAI-MEGAPAD-SOURCE-NEW
    0<> ABORT" OpenAI source allocation failed"
    DESK-AGENT-SOURCE! ;
```

Call checked construction inside a colon definition; KDOS `ABORT"` is a
compile-time word.

## Behavior

The provider builds bounded Responses requests with configurable host, path,
model, instructions, and output limits. It defaults to `store: false`, streams
SSE events, projects native capability schemas into function tools, runs tool
calls through Desk's Tool Gateway and approval policy, returns tool output, and
continues without relying on server-side conversation storage.

The source's configuration and transport can be inspected before ownership is
transferred:

```forth
source OPENAI-MEGAPAD-SOURCE-CONFIG
source OPENAI-MEGAPAD-SOURCE-TRANSPORT
```

Do not free or mutate the source while its provider exists.

## Credentials

Agent's Connection menu accepts an opaque credential through a masked prompt.
The prompt buffer is zeroed on submit, cancel, and shutdown. The provider copies
the bytes into `security/credential.f`; it never exposes a secret pointer,
prints the credential, adds it to a transcript, or stores it in Desk TOML.

Credential persistence is intentionally absent until the generic encrypted
vault and its key lifecycle are reviewed.

## Trust Gate

`megapad.f` does not install trust anchors. `NIO-OPEN` fails before DNS/TLS use
when KDOS has no applicable trust bundle, and bearer bytes are only written
after an authenticated TLS open.

The current deterministic profiles require no API key or network:

- `openai-provider` exercises HTTP/SSE, tools, approval, continuation, and
  cancellation through a recorded native transport.
- `openai-megapad` verifies physical composition, ownership, authentication,
  reconnect, clearing, zeroization, and stack balance.
- `agent-auth-ui` verifies masked entry and confirms fixture plaintext is absent
  from every emulator capture.

A live API test remains disabled until a current `api.openai.com` trust path is
reviewed and a credential-free handshake succeeds. An API key is needed only
after that gate.
