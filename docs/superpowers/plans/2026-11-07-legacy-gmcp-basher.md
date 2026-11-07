# Legacy-Style GMCP Autobashing Implementation Plan

**Goal:** Replace movement prediction with a GMCP-driven per-room mob roster for Imperian, continuing through known mobs after kills/removals.

**Approved choices:** GMCP events only, with no outgoing movement pause; continue the remaining roster while reconciling in the background. Adapt Legacy architecture, not its Achaea commands or external system dependencies.

**Architecture:** `Room.Info` determines room identity. `Char.Items.List` establishes the roster; room Add/Update/Remove events maintain it by numeric ID. Character events retain the existing real balance-cycle gate. Room identity and a fresh initial roster gate attacks in a newly reported room.

## Constraints

- Preserve global targeting and all three opaque reference forms, generic area lists and stored settings, one-target manual exceptions, protected/dead filters, passive Duality fire/ice, native autocuring ownership, `&&`, limits and refusal handling.
- No walk/heading correlation, pending move counter, exit prediction, mapper dependency, outgoing pause, automatic look or ql.
- Preserve flat exported folders and original creation timestamp; version0.1.7. Keep local reference XMLs untouched. One active Demonic package and Hunt mode alias.
- Ordered GMCP stream assumed; untagged lists cannot identify rooms independently. The user accepts the previous-room targeting window until new GMCP arrives.

## Task 1: Room roster and refresh coordination

Owner: room implementer; root provides behavioral RED and integration.

- [x] Replace room/bootstrap movement model. Valid changed `Room.Info` clears roster/retired/selections, advances generation/context, requests contents immediately when Hunt or pending target needs them. First identity preserves initial pending target context. Same ID updates metadata without resetting roster. Discard preidentity and non-room lists.
- [x] Keep ID-keyed room List/Add/Update/Remove and matching APIs. Remove movement/heading APIs and event handlers; balance-unavailable only updates readiness. Remove executionConfirmed/command attribution fields.
- [x] `dem.room.request(reason, blocking)` defaults true. Blocking makes roster unavailable; background retains usable roster. Coalesce same-room requests; blocking upgrades without renewing budgets, never downgrades. Immediate `Char.Items.Room ""`, IH once.2s, GMCP retry1s, timeout10s while hunting. Hunt-off pending/install query only GMCP once; enable upgrades to active cycle.
- [x] Background timeout records diagnostic without stopping usable Hunt; blocking missing identity/list stops. Stop/death/disconnect/reload cancel callbacks. Diagnostics retain reported identity/context and refreshError, remove movement fields.

## Task 2: Target retirement and integration

Owner: root.

- [x] Retire only submitted physical target. Kill/Remove/missing signals coalesce one background refresh; full snapshots reconcile without recursively refreshing. Preserve remaining ready roster and immutable pending attack/balance gate.
- [x] Guard successor targets from late/duplicate terminal text, including same-named mobs. Suppress ambiguous text retirement rather than consume a newer action. Keep retirement records scoped to room generation and ordered output evidence.
- [x] Normal status remains mode/target/reason; debug replaces movement fields with roster count, refresh mode/state/error and real wait reason.
- [x] Replace tests whose requirements belonged to deleted movement model; retain independent regression coverage. New tests cover outgoing/failure no barriers, Info/List order, duplicate/rapid Info, deltas, terminal orderings, background continuation/timing/upgrades/timeouts/cancellation, targeting contexts and refusal readiness.

## Task 3: Package, review and delivery

Owner: packaging implementer; root integrates/reviews/delivers.

- [x] Remove walk/heading generated triggers and contract helpers; assert absent. Keep target/status/grace/balance/slain/missing alias and trigger contracts. Update config0.1.7 and README for approved behavior and live assumptions.
- [x] Rebuild XML; run complete behavior, deterministic build, exact source parity, template/layout, timestamp/version metadata, alias/trigger and Lua syntax suite; git diff --check.
- [x] Fresh whole-branch review, material findings reproduced and fixed RED/GREEN, complete suite rerun.

Delivery: commit/push verified changes to Aeden15/Imperian main and compare remote/local SHA. Live acceptance remains separate: movement and consecutive kills without manual look/ih and one attack per confirmed balance cycle.

## Verification and review record

Baseline174 behavioral cases passed. Five Legacy-style behavior regressions failed against the prior runtime. Obsolete movement/heading guarantees were replaced; integrated package passed123 cases and all deterministic-build, source/XML, template/layout, metadata, alias/trigger, and syntax checks.

Independent review reproduced two Important terminal-provenance defects: refusal/restart discarded history, and authoritative name changes were not recorded. Five new regressions failed (123 passed, five failed). Root fix preserves history independently of active actions, records observed aliases from List/deltas by submitted ID and generation, and consults that history at terminal-message handling. `hunt.resetTerminalHistory()` runs on connection changes/death; refusal does not reset it. Complete rebuilt package now passes128 cases and all package checks. No Critical or Minor findings.

Review rulings: the accepted old-room targeting window and ordered untagged-list assumption stand. Ambiguous terminal text waits for GMCP reconciliation, retired IDs remain suppressed until explicit Add, and Hunt-off requests do not run timed recovery. Removed movement-model tests described obsolete guarantees and were replaced with the new behavior. Actual live combat/timing/installation remains separate. Reference XMLs remain outside the change and untouched.

## Review focus

- Same-name successor and duplicate terminal text must never retire the wrong ID.
- Background refresh must not pause known usable mobs or grant readiness.
- Repeated Info, early List and old timers must not resurrect another room's roster.
- Pending targets must cancel on received room transitions, without classifying early as players.
- Scope excludes new targeting queue/defenses/movement automation and any changes to user reference XMLs.
