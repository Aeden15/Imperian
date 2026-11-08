# Vitality and Nightfall wraith tracking

Implement inline using Superpowers execution, test-first regressions, independent final review, and fresh verification before commit/push.

## Approved requirements

- Track all eight types under dem.nightfall.wraiths: vigorous, whispering, translucent, fiery, midnight, glowing, reflective, ethereal. Fields: present, charges, enabled, id, target, location; unobserved fields unknown.
- Wraith triggers belong in Diabolist/Nightfall/Wraiths. Observe materialisation (including wrapped log form), exact charge counts, charge loss and vanishing. No commands, combat/target changes, predictive charges or expiry timers.
- Parse complete manual WRAITHS tables; preserve state on incomplete/malformed output. Distinguish enabled from present. Four simultaneous instances, maximum five charges. Ordinary movement and Nightfall defence loss do not imply disappearance.
- Reset observations on reload, connection change and death.
- Vitality consumed/cooldown triggers belong in Diabolist/Ritualism. Consumption clears armed state and blocks automatic recasting; refusal does not imply success/readiness or affect unrelated actions. Existing successful activation clears the block. No invented cooldown duration.
- ddef still attempts all seven commands once and proceeds after a refusal with fresh readiness. Optional maintenance skips unavailable Vitality and continues other defences.
- Rebuild XML, run all tests, review material findings, commit/push current branch normally; exclude local mapper export.

## Tasks

- [x] Add failing state, parser, Vitality and XML-contract regressions.
- [x] Implement Nightfall observation/parser and Vitality outcome handling; wire XML/lifecycle.
- [x] Verify full suite and review; fix material findings with regression tests.
- Delivery: commit verified changes, push normally, and verify the remote SHA.

## Review focus

Partial snapshots must not erase known entities; newer events must survive an older table row; repeated lifecycle messages must not fabricate instances; cooldown refusals must not unblock unrelated or accepted actions; lifecycle resets must discard in-progress snapshots.

## Verification record

- Initial regressions failed on missing wraith state/parser/triggers and Vitality handling before implementation.
- 36 anonymous wraith-event lines extracted from the supplied HTML log replay through the generated patterns/captures and actual embedded Lua bodies.
- Independent review found truncated-row overwrites and premature retirement of a confirmed Vitality action. Three targeted regressions failed before their fixes and passed afterward.
- Final suite: 164 behavioral +14 GUI tests passed, along with deterministic XML rebuilds, embedded-source synchronization, actual alias/trigger contracts, folder placement, all Lua syntax and whitespace checks.
- Passive scope remains explicit. No inferred expiry/cooldown timers, active wraith commands, automatic queries, player-combat changes, or unrelated mapper export.
