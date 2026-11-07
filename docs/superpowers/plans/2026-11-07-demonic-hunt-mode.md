# Demonic Hunt Mode Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement and verify this plan inline.

**Goal:** Deliver a self-contained Mudlet package with shared targeting and area-specific Diabolist hunting, then commit and push to Aeden15/Imperian.

**Architecture:** Readable Lua modules are bundled into the existing XML. System owns targeting, balances, room GMCP, persistence, and lifecycle. Ritualism builds a single Duality command; the hunting scheduler alone submits hunting attacks.

**Tech stack:** Lua 5.1-compatible code, Mudlet GMCP/events/triggers, PowerShell XML bundling and verification.

**Spec:** The agreed design in this chat, including the final correction: `dem.target` is one unchanged word (`fido`, `fido1234`, or `1234`), never separate name/ID fields.

## Global constraints

- All globals/functions live under `dem`; preserve the existing XML folders.
- The global command separator is `dem.separator = "&&"`; shared command joining uses it. The user's screenshot confirms the game is already configured accordingly.
- Hunt mode: name `Hunt mode`, pattern `^hunt$`, under Aliases / Demonic / System / Autobasher.
- Shared Targeting script under Scripts / Demonic / System; all balance/equilibrium text triggers under Triggers / Demonic / System / Balances.
- Explicit player/denizen target aliases; player selection disables hunting, denizen selection overrides the allowlist for that target only.
- Persist empty-by-default area allowlists and 30% HP / 10% mana limits; never persist active hunting or targets.
- GMCP primary, combat-text fallback for vitals/readiness; no healing, movement, or class defense automation.
- Duality learned by default: one `trace fire ice <target>` command, 18 mana, confirmed balance recovery rather than timer-driven readiness.

## Review focus

- A late kill/error from an old attack must preserve a newly selected manual target.
- Movement must discard old roster/area without resetting a pending cooldown.
- Duplicate/stale ready packets must not create additional attacks.
- Missing fields/maxima must not become permission to attack.
- Reload/uninstall must leave no duplicate handlers, timers, or late sends.

## Task 1 — Package harness and shared services

- [x] Add executable tests against scripts extracted from the XML; observe failure on the empty package.
- [x] Implement core lifecycle/persistence, opaque targeting, Duality construction, balances and vitals.
- [x] Verify all three target forms, invalid input, actual output commands, missing data, and text fallback.

## Task 2 — Room tracking and hunting

- [x] Implement room snapshots/deltas and per-area name lists with dead/protected exclusions.
- [x] Add the toggle, manual override, one-action gate, prompt scheduling, and watchdogs.
- [x] Verify switching targets mid-cycle, kill/error ordering, moving while pending, area transitions, and safety stops.

## Task 3 — Bundle, review, and publish

- [x] Bundle scripts, aliases, and triggers into the existing XML; document installation and APIs.
- [x] Run the full XML/Lua/behavior suite, then obtain an independent code review and fix material findings with regression tests.
- [ ] Commit reviewed files and push a fast-forward update to the user's Imperian repository; verify the remote commit.

## Execution record

- Source initially had no Git repository; attached the confirmed remote and based a dedicated local feature branch on origin/main, which contains only README.md. Existing XML/config were preserved.
- User requested multitasking during implementation: parallel workers own shared services and room/hunt modules; root owns bundling, integration, and tests. No further design or integration approval is needed.
- Baseline: 27 behavioral tests failed against the empty XML, confirming missing implementation. Final integrated suite passes 45 behavioral tests, XML placement and embedded Lua syntax checks, and repeat-build stability.
- Ruling: bundle from an immutable template of the original folder layout rather than using the generated output as input. This prevents recursive inclusion on rebuild and makes source/template changes reproducible; edit sources/template rather than generated XML.
- Independent review found one material refresh/removal race. Its regression failed before the fix and passes afterwards: retain known same-room selection ownership during refresh, while fresh roster validation still gates attacks. Documented Package Manager's optional outer wrapper.
- Live packet ordering, combat messages, and gameplay are not verified by the local suite. They remain the documented manual acceptance checks.
