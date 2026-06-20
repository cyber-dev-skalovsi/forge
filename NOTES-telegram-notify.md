# WIP — Telegram push notifications

Draft: notify on pushes via the existing `push-listener.js` webhook path instead
of a second listener. Not finished — the notification send is stubbed behind a
`NOTIFY_URL` that is not wired up yet.

## Sketch

- `push-listener.js` already receives every push with HMAC verification.
- Add an optional notify step: when `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID`
  are present in `.forge-env`, POST the push summary to the Telegram Bot API
  after a successful `forge.sh push`.

## Open questions

- Keep it in `push-listener.js` or a separate module imported by it?
- Should a failed notification fail the push? (Current leaning: no — log and
  continue; a failed backup is worse than a failed chat message.)
- Rate limiting: Telegram allows ~20 msg/min/chat, plenty for a single user.

## Status

Stub only. The `runPush()` close handler logs a placeholder. Do not merge until
the send path exists and is tested against the real push flow.
EOF