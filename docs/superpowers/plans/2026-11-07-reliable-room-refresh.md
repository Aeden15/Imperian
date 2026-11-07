# Reliable Room Refresh Implementation Plan

**Goal:** Automatically reconcile hunting room state after movement and kills, using GMCP then `ih`, while preserving the user's newer export layout and timestamp.

**Approved behavior:** No prompt barrier. Changed room identity invalidates old targets and requests `Char.Items.Room ""`. Coalesce requests; retry once after one second; send `ih` once after another second; block attacks until confirmed identity and full roster; stop after ten seconds if unresolved. Standard outgoing movement invalidates old room eligibility; confirmed failed movement permits reconciliation of the last known room. Item lists cannot establish room identity. Remove-before-kill must still reconcile once. Preserve action/cooldown gates and existing generic/area/targeting behavior. Include `You detect nothing here by that name.` and refresh diagnostics.

## Tasks

- [x] Add and observe failing regressions for prompt-independent refresh, retry/fallback timings, movement, terminal ordering, and cancellation.
- [x] Implement one room refresh coordinator and integrate movement/failed-movement events, kill reconciliation, and status.
- [x] Adopt the current flattened export layout in the immutable template/build/tests; preserve `created = "2026-11-07T01:33:06-06:00"`, restore metadata, and synchronize embedded sources.
- [x] Run the full suite, obtain independent review, and fix findings with regressions.
- Delivery: commit/push the verified tree and confirm the remote SHA matches.

## Verification focus

Room.Info before/after prompts without more text; early/stale lists; rapid movement and missing identity; failed movement; inventory ignored; Remove/Kill/Missing ordering; fallback exactly once; off/disconnect/reload cancellation; old action and newer target independence; deterministic build and all source/XML parity.

## Execution record

- Base: 30c4aba. The user's XML/config export is modified locally; all seven embedded Lua sources match the readable files. Original export/config backed up under this plan's ignored scratch directory before integration.
- Native packet lists do not carry room/request IDs. Preserve the documented ordered-stream assumption; local tests cannot prove live server ordering.
- RED run against the existing export: 65 passed / 13 failed for changed behavior. Integrated run: 80 passed / 0 failed plus deterministic build, source synchronization, layout/metadata/alias/trigger contracts, and Lua syntax.
- Two older delta-only continuation tests now supply a full reconciliation roster before expecting another attack; partial updates intentionally cannot satisfy a pending full refresh.
- Independent review identified unchanged Room.Info replies from an outstanding `look` being counted as movement confirmation. Two regressions failed before the fix; unchanged identities now leave movement pending, while genuine transitions and WrongDir remain valid confirmations. A return-to-origin sequence remains supported.
- Final local result: 83 behavioral tests pass; XML/source parity, exported layout/metadata, one active alias of each kind, all missing-target fixtures, deterministic rebuilds, and Lua compilation pass. Status also retains the initiating refresh reason.
- A true same-ID movement cannot be distinguished from a repeated old-room update using these packets alone; it remains unconfirmed and times out instead of allowing an old-room attack.
