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
| [schema/news.json](schema/news.json) | `GET /v1/news` |
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

## Identity (`user_hash`)

`POST /v1/mobile/sessions` checks `user_hash` by the inbox's identity mode:

| Mode | No hash | Wrong hash |
|---|---|---|
| `off` | accepted, not verified | ignored |
| `recommended` | accepted, not verified; `403` for a user who has logged in verified before | `403`, for a new user too |
| `enforced` | `403` | `403` |

`403` is `identity_verification_failed`. A wrong hash is never accepted, so a mistake in `identity_secret` shows at
the first login instead of leaving users unverified.

## Replies

- The app sends `content.reply_to` (a message id) with a `text` or an `attachment`. The server keeps it where the
  panel keeps an operator's reply, so the panel shows the quote; one the user cannot see is `400 reply_to invalid`.
- Every message carries `reply_to`: null, or `{id, sender {type, name}, excerpt, kind}`. An operator replying in the
  panel produces the same. `excerpt` is plain text, at most 120 characters (a file's or an image's name when it has no
  caption); `kind` is `text`, `image` or `file`.
- A deleted message keeps its `sender` and has `excerpt: null`; one the user never saw (a private note) or that is gone
  also has `sender: null`. The SDK shows `strings.quote_deleted` for either. A quote is not re-sent when the quoted
  message is deleted later: the app applies the deletion's `message.updated` to quotes of that id itself.

## Flow and the composer

- A conversation (REST) and every `conversation.updated` carry `flow {active, awaiting}`, plus `flow_id` and
  `node_id` while it runs. The SDK shows or hides its composer by this alone.
- `active: true`: a flow drives the conversation and the composer is hidden, except with `awaiting: "text"`.
  `awaiting` is `menu` (buttons, a language question too), `text`, `form`, or null while nothing is asked yet (a wait
  step).
- `active: false` once the flow ends (with an END step or without one), stops because a person replied, or hands
  over. Each of these sends `conversation.updated`; a new flow step sends it right after its message.

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
| `66`–`70` | replies: the user to an operator, an operator (panel) to an image, to a deleted message, the client's `reply_to`, one that must fail |
| `71`–`74` | `conversation.flow`: waiting on buttons, on text, ended; one that must fail |
| `90`–`98` | must fail: they prove the schema refuses what it should |

Each file stands alone: the fixtures are cases, not one recorded conversation, so their `seq` and
`created_at` are not meant to be read in sequence.
