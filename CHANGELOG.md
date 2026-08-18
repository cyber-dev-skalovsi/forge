# Changelog

All notable changes to the forge are documented here. Dates are local.

## [Unreleased]

## [0.4.0] — 2026-08-12

### Added
- Local end-to-end proxy verification script (`worker/verify-local.sh`) that
  round-trips a 5 MB blob through `wrangler dev` and compares git object IDs.
- Zeabur deploy config (`zeabur/`) as an explored-but-unused always-on option.
- Worker observability and pinned toolchain versions.

### Changed
- Rebranded from Forgejo to Talon: gold theme, logo, account `talon`.
- Auto-push webhook listener with HMAC verification and coalesced concurrent
  pushes.
- Lean UI: only code, browse and releases enabled on a private forge.

## [0.3.0] — 2026-01-24

### Added
- `forge.sh push` / `pull` / `status` / `drill`: portable AES-256 encrypted
  snapshots to Backblaze B2 via restic in a container.
- Local dump script as belt-and-braces on top of the cloud snapshots.

### Fixed
- Webhooks to `host.docker.internal` blocked by the SSRF guard until
  `FORGEJO__webhook__ALLOWED_HOST_LIST` was set.

## [0.2.0] — 2025-12-12

### Added
- Cloudflare Worker reverse proxy streaming git smart-HTTP unbuffered.
- Local compose variant using a named volume for Windows/macOS.
- Optional public quick tunnel behind the Worker.

## [0.1.0] — 2025-11-28

### Added
- Self-hosted single-user Forgejo on an Oracle Always Free ARM box.
- Tailscale serve/funnel for private and public HTTPS reachability.
- Nightly restic backup to cloud storage plus a restore drill.