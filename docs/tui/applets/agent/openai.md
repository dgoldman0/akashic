# Native OpenAI Responses Provider

The OpenAI provider is implemented entirely in native Akashic using KDOS
services. It does not invoke Python, a host bridge, Codex CLI, or an emulator
service.

## Modules

```text
akashic/tui/applets/agent/providers/openai/config.f
akashic/tui/applets/agent/providers/openai/request-codec.f
akashic/tui/applets/agent/providers/openai/event-codec.f
akashic/tui/applets/agent/providers/openai/responses.f
akashic/tui/applets/agent/providers/openai/source.f
```

`responses.f` implements the provider-neutral `APROV` callbacks over an `NIO`
port. `source.f` owns the complete construction environment: one allocation
embeds OpenAI configuration, a zeroizing credential adapter, and a KDOS TLS
transport. These renderer-free internals own no hardware or presentation, but
remain part of the Agent applet rather than a standalone provider product.

```forth
REQUIRE tui/applets/agent/providers/openai/source.f

: USE-OPENAI  ( -- )
    OPENAI-SOURCE-NEW
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

Each session builds its requests from a configuration. An ordinary turn's
session uses the provider's configuration, which follows the selected model.
A designated turn's session gets its own copy, which the provider's
designator configures for the model the turn names. The designator has the
signature `( designation config context -- status )`, returns an `ARSET-`
status, and is set with `OPENAI-PROVIDER-DESIGNATOR!`. The copy lives as long
as the session, so a designated turn never changes the selection. A provider
without a designator refuses a designated turn with `OAIR-S-MODEL`. So does a
designator that refuses the turn; one that runs out of room is
`OAIR-S-CAPACITY`. `OAIR-SESSION-CONFIG` gives the configuration a session
uses.

A session sizes a turn's input (its history and prompt as JSON), the
request body and the tool history it gathers to what they hold, so only
memory bounds them. Each encoder writes into the buffer it is given and,
when that is too small, returns the length it needs with
`OAIREQ-S-CAPACITY`; `0 0` asks for the length alone. The session then takes
a buffer of exactly that length and writes again. The body is lent to the
HTTP request, which sends it after the head without copying it, and the
head's buffer starts at 1 KiB and doubles until the head fits. Each buffer
is zeroed before it is freed. The encoders check that the input and history
they are given are JSON, and the session checks each history item, bounded
by their own length (`JSON-VALID-LIMIT?`) rather than the process-wide
64 KiB gate of `JSON-VALID?`. `OAI-TURN-INPUT-U` gives the exact bytes a
turn with no history takes, and the provider reports them through
`APROV-INPUT` with a room of -1.

The request body remains owned until a valid 200 SSE response accepts it. On
the first 401 for one logical request, the provider closes the model transport,
starts `AAUTH-REFRESH`, waits while the runtime pumps authentication, and then
rebuilds only the HTTP envelope with the rotated access token. The bearer wire
buffer is cleared after each send, the replayed body is byte-identical, and a
tool result enters model history only after successful response headers. A
second 401 for that request is terminal; a later, newly constructed request
receives its own single retry allowance.

The source's configuration and transport can be inspected before ownership is
transferred:

```forth
source OPENAI-SOURCE-CONFIG
source OPENAI-SOURCE-TRANSPORT
```

Do not free or mutate the source while its provider exists.

## Credentials

Agent's Connection menu accepts an opaque credential through a masked prompt.
The prompt buffer is zeroed on submit, cancel, and shutdown. The provider copies
the bytes into `security/credential.f`; it never exposes a secret pointer,
prints the credential, adds it to a transcript, or stores it in Desk TOML.

Credential persistence is intentionally absent until the generic durable
secret store and its root-key lifecycle are available.

## Trust Gate

`source.f` does not install trust anchors. `NIO-OPEN` fails before DNS/TLS use
when KDOS has no applicable trust bundle, and bearer bytes are only written
after an authenticated TLS open.

The current deterministic profiles require no API key or network:

- `openai-provider` exercises HTTP/SSE, tools, approval, continuation,
  asynchronous token rotation, exact-body 401 replay, one-time history commit,
  terminal repeated authorization failure, and cancellation through a recorded
  native transport. It also checks designated turns: without a designator, or
  with one that refuses or runs out of room, the turn starts nothing. With
  one, the request names the designated model while the provider's
  configuration stays as it was.
- `test_agent_input.py` checks the input room against what the encoder
  writes, at the buffer's exact boundary.
- `openai-source` verifies source composition, ownership, authentication,
  reconnect, clearing, zeroization, and stack balance.
- `agent-auth-ui` verifies masked entry and confirms fixture plaintext is absent
  from every emulator capture.

A live API test remains disabled until a current `api.openai.com` trust path is
reviewed and a credential-free handshake succeeds. An API key is needed only
after that gate.
