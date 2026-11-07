# Faster Arrival Refresh and Concise Status

**Goal:** Add one generic movement-direction trigger, shorten active roster fallback to 0.2 seconds, preserve shared arrival/GMCP cycles, and make ordinary Hunt status concise.

**Approved interfaces:** System/Autobasher trigger `Room entered`, pattern `^You walk (\w+)\.$`, body `dem.room.onEntered(matches[2])`; validate supported directions in Lua. `hunt status` calls `dem.hunt.status(false)` through an optional debug capture, while `hunt status debug` calls it with true. Keep detailed diagnostics only in the latter.

**Behavior:** Immediate GMCP after confirmed entry or terminal target event. If no full roster arrives within 0.2 seconds, send ih once. Keep the one-second bounded GMCP retry, ten-second timeout, and all existing combat/identity/resource checks. Entry text and corresponding Room.Info share one arrival transaction; no duplicate movement counting, invalidation of already-fresh contents, renewed grace delay, or duplicate IH. Room identity still requires GMCP confirmation.

## Tasks

- [x] Observe failing entry/timing/concise-status regressions against existing XML.
- [x] Implement arrival coalescing and fast fallback, add the XML trigger/status alias, and keep release docs/metadata current.
- [x] Rebuild XML and run the full behavioral, source-parity, alias/trigger, layout, and syntax checks.
- [x] Obtain independent review and fix material findings with regressions. Delivery uses the approved commit/push workflow after the final full-suite check.

Parallel ownership: room arrival logic; XML packaging/docs; root status and Lua regressions/integration. Preserve the current flat export layout, creation timestamp, namespace, generic targeting, area lists, Duality, &&, and game autocuring ownership.

## Verification record

The existing XML produced 84 passing and 10 failing behavior cases for the changed requirements. After integration, all 95 behavioral tests pass, together with exact embedded-source parity, deterministic rebuilding, all twelve direction captures, concise/debug alias dispatch, preserved layout/metadata, and Lua compilation.

Outgoing movement alone keeps targets invalid but does not spend the IH fallback in the old room. Observed entry text or Room.Info starts the 0.2-second arrival grace; the ten-second safety timeout remains. A slow-movement test uses a 1ms margin at its final observation to avoid floating-point subtraction artifacts; production timing is unchanged at 0.2 seconds.

## Follow-up: Finish Hunt Room Refresh and XML Synchronization

The user approved resolving three independent-review findings before shipping. Keep text-correlation eligibility separate from room readiness. Initial identity and synthetic failed-movement snapshots cannot consume future walk text, though the first live identity can acknowledge an existing text-only arrival. Genuine Info-first transitions may pair with walk text until the next prompt; prompts close only unmatched text correlation and never gate requests or readiness. Same-direction duplicate suppression expires once identity and full contents complete an arrival. Duplicate intermediate identities cannot consume later unidentified text-only arrivals.

Seven additional behavioral tests cover those cases, failed-movement snapshots, prompt closure, Info-first coalescing, and the first identity acknowledging an existing arrival. Before fixes, the full suite reported 97 passing and 5 failing tests. After fixes and rebuilding, it reports **102 passed, 0 failed**, with deterministic builds, embedded-source parity, preserved layout/metadata/timestamp, exact alias/trigger contracts, and Lua syntax all passing.

The independent review's three Important findings are resolved with regressions. The server stream ordering assumption remains explicit: arbitrary walk text crossing later arrivals and identical untracked same-direction messages before confirmation cannot be disambiguated from available payloads. Live movement and consecutive-kill acceptance remain separate from simulated verification.
