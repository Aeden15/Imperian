# Flexible Movement Recognition and Room Recovery

User approved implementation and workspace/XML synchronization. Base: 1998c922c1da6d2595b2f5ca0b5993df22c2a4e8.

## Contracts

- Movement prefix: `^You\s+walk\s+([A-Za-z]+)(?=\s|[.,!?;:]|$)` calls `dem.room.onEntered(matches[2])`; validate supported directions in Lua, independent of following text.
- Native heading: `^(.+?)\.\s+(\d+)(?:\s+\([^)]*\))?\.?$` calls `dem.room.onHeading(matches[2], matches[3])`. A successful walk opens one frame tied to its movement token. Only its next heading plus newly received Room.Info matching normalized name and positive ID can override stale expected exits/repeated-ID rejection. Support Info before/after heading and tracked walk. A prompt closes eligibility for a missing heading, but preserves a captured heading waiting for Info. Later movement/replacement/death/reset invalidates obsolete proof. Cached Info alone/LOOK/no-walk/inventory/early lists cannot recover.
- Commit recovery once, retire only the accounted-for prefix through its frame, keep older unaccounted and later queued commands blocked, then query a fresh full roster. Do not restart retry/IH/timeout budgets for the same arrival or discard a normal fast-path already-fresh roster. Unknown evidence remains blocked.
- Death cleanup is a one-time transition: `dem.onDeath()` stops Hunt, clears pending target/room state/timers/action, invalidates readiness, and preserves GMCP resource authority. Revival accepts fresh data without enabling Hunt. `dem.balances.clearForDeath()` releases the action/readiness without resetting numeric authority; connection reset clears all authority.
- HP/maxHP and MP/maxMP adopt persistent GMCP authority independently on any explicit field, including invalid fields. First adoption clears both text-derived members; partial packets retain only prior GMCP members. Invalid explicit fields become unknown and text cannot repair adopted pairs. Boolean balance/equilibrium text fallback remains separate.
- Keep normal status concise. Debug distinguishes historical stop reason and actual blocking movement/expected destination/recovery reason.

## Steps

- [x] Add and observe failing regressions for recovery, death/revival, and resource units.
- [x] Implement room recovery and vitals/death in separate owned files; restore overwritten Demonic metadata as 0.1.5 and update XML trigger/contracts/docs.
- [x] Rebuild and pass full behavioral, deterministic-build, exact source parity, layout/timestamp/metadata, aliases/triggers, Lua syntax suite.
- [x] Independent review and material findings fixed RED to GREEN. Delivery uses the approved commit/push workflow after final verification.

Preserve original exported layout/timestamp, targeting APIs/pending behavior, area lists, Duality, game curing ownership, &&, GMCP-first IH0.2/retry1/timeout10 and immutable attacks except actual death cleanup. Mapper XML is an independent user-supplied reference; do not edit or package it into Demonic. Live ordering remains external acceptance.

## Verification record

Initial old-XML regressions: 128 passed, 20 failed (missing native-heading recovery plus resource/death defects). Integrated source changes passed 148 tests; the next queued walk's Info-before-text case then failed and was fixed without retaining prior heading evidence. The rebuilt XML passed 149 behavioral cases before independent review.

Independent review reproduced two Important gaps: heading-first proof could be consumed by an earlier queued token, and ordinary identity acceptance ignored contradictory native headings. Six order/ID/name regressions produced 150 passed and 5 failed before fixes. Current-frame proof is now attempted before ordered packet consumption; contradictory headings roll back readiness and that identity acknowledgement while preserving the submitted attack. Matching normal fast-path headings preserve their existing roster.

Final rebuilt XML passes **155 behavioral cases**, actual heading trigger dispatch, flexible-prefix and heading fixtures, deterministic rebuilding, exact seven-module parity, layout/timestamp/0.1.5 metadata, aliases/triggers, and Lua compilation. No minor findings were deferred. Live transport/timer ordering and indistinguishable duplicate untracked walk messages remain documented acceptance limits. Fresh packet data may be reused within its unchanged outgoing batch, but each recovery still requires a new matching native heading and fresh roster. The untracked mapper export is preserved as local reference, not included in the package or commit.
