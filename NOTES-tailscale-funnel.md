# Tailscale Funnel notes

Draft notes from experimenting with public HTTPS via Tailscale Funnel instead of
the Cloudflare quick tunnel. Not merged — the quick tunnel + Worker won because
it does not require Funnel to be enabled in the Tailscale admin console.

## Why Funnel was considered

- One less moving part: no `cloudflared`, no Worker to keep in sync.
- `tailscale funnel` terminates TLS at the tailnet edge for free.
- The origin stays bound to `127.0.0.1` — nothing opens a public port.

## What stopped it

- Funnel must be enabled per-host in the admin console; on a work-managed
  account that needs approval.
- `tailscale serve`/`funnel` process isn't persistent by default; it needed a
  systemd unit we didn't want to own on a shared box.
- The Worker gives a stable `workers.dev` hostname independent of tailnet state,
  which the ephemeral `*.trycloudflare.com` does not — but Funnel URLs are also
  per-node and would churn.

## TL;DR

Funnel is strictly better when you control the tailnet account and want a
persistent public name. For this work-managed machine, the Worker is the safer
default.
EOF