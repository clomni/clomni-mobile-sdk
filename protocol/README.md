# Clomni mobile messenger protocol (v1)

The contract between the server and the mobile SDKs (`Channel::AppSdk` inbox). The brief is
[docs/ui-reference.html](../docs/ui-reference.html), section 8 (§5 protocol, §6 Mobile API); the audit
is [docs/audit.md](../docs/audit.md) (§15 maps Clomni messages to these types).

| Schema | What |
|---|---|
| [schema/message.json](schema/message.json) | server → client message (REST and WebSocket) |
| [schema/client-message.json](schema/client-message.json) | client → server, `POST /v1/conversations/{id}/messages` |
| [schema/event.json](schema/event.json) | WebSocket frame `{event, data, ts}` |
| [schema/config.json](schema/config.json) | `GET /v1/mobile/config` |
| [schema/push.json](schema/push.json) | Clomni keys of an FCM / APNs push |
| [openapi.yaml](openapi.yaml) | Mobile API v1 (REST), OpenAPI 3.1; the realtime socket is described in its `info` |
| [strings.json](strings.json) | the SDKs' UI texts in az, en and ru (see below) |

Rules that the schemas encode:
- Within v1 only additions: a new field, type or event. Removing a field, renaming it or changing its type is not allowed.
- An unknown `type` is valid: the client shows it with `fallback_text`. Unknown fields are allowed and skipped.
- Ids are prefixed strings (`msg_`, `conv_`, `flw_`, `frm_`, `upl_`, `usr_`); clients never parse them or sort by them; order is `seq`.
- Times are UTC ISO 8601.

The Mobile API's endpoints, auth and errors are in [openapi.yaml](openapi.yaml) (CM-050). It refers to the schemas
above for messages, client messages and config instead of repeating them.

## Validate

```bash
cd protocol
npm ci
npm run validate   # schemas, examples, fixtures
npm run lint       # openapi.yaml, including that every example matches its schema
```

CI (`.github/workflows/protocol.yml`) runs the same commands on every pull request that touches `protocol/`,
and on `main`.

`examples/brief/` holds every JSON example of the brief; `fixtures/` (CM-011) the cases both SDKs render.
Each folder's `index.json` names the schema a file must pass, or `"valid": false` for one that must fail.

## UI texts (`strings.json`)

Every text the SDKs show that does not come from a message: tabs, dates, statuses, form errors. Keys are the
same in az, en and ru; `%d` stands for a number and `%@` for a text (a time, for `away_until`).

- `GET /mobile/config` returns `strings` for one language: this file's set, with the inbox's own overrides
  (`appearance.strings.<lang>`, set in the panel) on top.
- Each SDK carries the same table built in, so a minimal config, or none yet, still reads well.
- A new text is added here first, in all three languages, then to both SDKs. `npm run validate` fails if a
  language misses a key, has an empty text, or its placeholders differ from az.

Text on the brand colour (`brand.on_primary_color`) is always sent. When the inbox does not set it, the
server picks white if white reaches a WCAG contrast of 4.5:1 on `primary_color`, otherwise black; the SDKs use
the same rule for a config that lacks it.

## Fixtures

`fixtures/` is what Android and iOS both render in their screenshot tests (CM-070, CM-080); a renderer
change that breaks one of them breaks both platforms the same way. `index.json` gives each file a `note`
saying what the screen must show.

| Files | Cases |
|---|---|
| `01`–`06` | text: bot, operator markdown, user with `client_id`, long, emoji only, unsafe link (`javascript:` is shown as plain text) |
| `07`–`08` | three-language greeting with language buttons, before and after the choice |
| `09`–`12`, `50` | Apar flow, four levels: A → S (chips + back) → U → N (handoff / end) → END |
| `13`–`15` | button title over 80 characters, ten buttons, buttons without text |
| `16`–`18` | image with and without dimensions, PDF |
| `19`–`21` | forms: contact, every field type, submitted (same `seq`, read-only) |
| `22`–`25` | system: queue position, operator joined, closed, an event the client does not know |
| `26`–`28` | card, carousel, rating (phase 2: a 1.0 SDK shows `fallback_text`) |
| `29`–`32` | unknown type, unknown fields, operator without avatar, Russian |
| `33`–`41` | WebSocket frames, including one unknown event |
| `42`–`44` | config (full and minimal), push |
| `45`–`49`, `51`–`52` | client messages: text, button, back, form, attachment, end, rating |
| `90`–`98` | must fail: they prove the schema refuses what it should |

Each file stands alone: the fixtures are cases, not one recorded conversation, so their `seq` and
`created_at` are not meant to be read in sequence.
