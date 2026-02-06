# Zeabur free plan — volume mount check

Quick probe to settle the one open question about Zeabur's Free plan before
committing to it: can it actually mount a persistent volume?

A copy of Forgejo was deployed to `forge-test.zeabur.app` via the dashboard
steps in `../README.md`, and the volume mount (`data` -> `/data`) was attempted
on the Free plan.

## Result

| Question | Outcome |
|---|---|
| Free plan mounts a volume? | **No** — the `Volumes` tab is present but mounting is gated to paid plans. |
| Filesystem persists across restart? | No — ephemeral; any repo is destroyed on the next restart. |
| Verdict | Zeabur is ruled out, matching the README's "Honest limitations". |

## What this means

The portable encrypted model (`.forge.sh push`/`pull` to B2) remains the
primary path. This branch exists only to record the probe and is not merged —
the deploy config stays as a reference for if a paid tier is ever used.

To reproduce, create a service from `codeberg.org/forgejo/forgejo:15`, then try
to attach a volume on the Free plan.
EOF