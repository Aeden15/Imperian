# Stuck Room Identity and Pending Target Classification

**Goal:** Accept correctly correlated GMCP room identities despite a missed intermediate packet or intervening prompt, and wait to classify manual targets until a current full roster is confirmed.

**Approved design:** Movement tokens have immutable context IDs distinct from refresh generations. Explicitly tracked walk acknowledgements survive prompts. Connection-local validated Room.Info exit metadata correlates received identities to expected movement destinations; it never grants identity or readiness alone. Skip missing Info only across a proven path whose earlier entries succeeded. Unknown paths retain conservative ordered matching and bounded timeout. Duplicate intermediate packets and stale look replies must not authorize attacks.

`dem.room.contextId` identifies the latest movement context (initially zero; a batch selects its last token). Refreshes and replies do not replace it. `dem.targeting.kind = "pending"` retains the opaque reference and its context while automatic classification waits. `dem.targeting.resolvePending()` runs before the scheduled Hunt step, even with Hunt off. A current full roster resolves to a living denizen or the existing player fallback. A later movement, replacement, clear, or connection reset cancels pending selection; current-movement replies preserve it. Existing explicit targeting APIs remain immediate. Pending selection never alters the submitted attack.

## Execution

- [x] Add and observe failing behavior regressions against 75b9293.
- [x] Implement room token/context recovery, pending targeting/scheduling, debug diagnostics, and 0.1.4 metadata/docs in separate owned files.
- [x] Rebuild XML and pass the full behavioral, deterministic-build, source-parity, layout/metadata, alias/trigger, and syntax suite.
- [x] Independently review and fix material findings RED to GREEN. Delivery uses the approved commit/push workflow after final verification.

Preserve the exported layout and creation timestamp, exact aliases, 0.2-second IH fallback/one-second retry/ten-second timeout, immutable attacks/balance gates, area lists/generic references, Duality, autocuring ownership, and &&. Keep normal status concise; detailed status includes correlation state and rejection reason. Live movement/kill acceptance remains external; cached exits or untagged lists never establish a room by themselves.

## Verification record

The first behavior run reproduced 11 failures with 109 passing cases; the debug regression added a twelfth failure. Integration then reproduced two additional boundary cases (mixed hinted/unhinted movement accounting and subscription before off-Hunt pending targeting).

Independent final review reproduced four Important findings: prompt cancellation of pending classification, an ignored early roster while Hunt is off, an ambiguous repeated destination acknowledging a later unexecuted command, and WrongDir retiring an unresolved successful unhinted entry. Four committed regressions first produced **123 passed, 4 failed**. After fixes, the rebuilt XML passes all **127 behavioral cases** plus deterministic rebuilding, exact seven-module source parity, preserved layout/timestamp and 0.1.4 metadata, alias/trigger contracts, and all embedded/config Lua compilation. No minor findings were deferred.

Live packet ordering and Mudlet timer dispatch still require in-game acceptance. Arbitrarily delayed untagged item lists cannot be assigned to earlier rooms; the documented ordered-stream assumption remains in force.
