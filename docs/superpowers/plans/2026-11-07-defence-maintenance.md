# Demonic defence maintenance implementation plan

Implement the approved chat design inline with Superpowers execution, TDD, final independent review, and verification before commit/push.

## Requirements

- Repair exported script order (System before Diabolist, bootstrap last), unfinished class script, and undefined `mal`/`nightfall` trigger state.
- Preserve imported class confirmations through the build; add Ritualism alias `Defs`, `^ddef$`, calling `dem.defences.toggle()`.
- Maintenance toggles independently of Hunt, defaults off, pauses during Hunt, and resumes afterward. Reset on death/connection/reload.
- Order: summon ouroboros, demon armor, demon regeneration, demon soulmask, demon syphon, trace vitality me, nightfall. Summon confirmation is required before any defence.
- Use confirmed activation/loss state. Nightfall off: `The darkness around you dissipates.` Missing Vitality and other loss/cooldown messages are deferred.
- One shared pending action. Nightfall uses equilibrium, Vitality uses balance, undocumented commands require confirmation followed by fresh ready prompt. Ten-second unconfirmed-command timeout disables maintenance without retries.
- Hunt shields at <=40% HP using `trace inversion hammer me`, 18 mana, confirmed balance cycles; shielding overrides HP stops, preserves MP stops and target history, resumes attacks above 40%.
- Keep unrelated edits; include GUI dependencies of generated XML, exclude mapper export. Push current codex/legacy-gmcp-basher branch to origin (Aeden15/Imperian), no force or main merge.

## Tasks

- [x] Add and observe failing startup, alias/trigger, maintenance, and Hammer regressions.
- [x] Implement skill/class modules, shared action sequencing, lifecycle and XML generation repairs.
- [x] Run complete behavioral/GUI/XML/Lua suite and review; fix material findings with regression tests.
- [ ] Commit verified dependencies and fixes, push normally, verify remote SHA.

## Acceptance

Actual embedded scripts load in XML order. Actual aliases/triggers execute without the logged nil errors. Confirmed commands advance once; stale packets/timers cannot grant recovery. Maintenance and Hunt never compete. Local simulated tests are separate from live Mudlet acceptance.

## Execution evidence

- Independent Superpowers review found one material stale-readiness issue. A dedicated regression reproduced it; action-scoped readiness observations now prevent a missing or one-bit GMCP prompt from advancing maintenance.
- Final verification: 146 behavioral and 14 GUI tests passed; deterministic XML builds, embedded source synchronization, actual aliases/triggers, startup order, Lua syntax and `git diff --check` passed.
- Vitality consumption/cooldown and missing loss messages remain explicitly deferred. Live native widgets and server message ordering require live acceptance.
