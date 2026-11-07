# Refused Attack and Movement Recovery

Base881bfbe. New user logs show a divine-grace attack refusal retained as an unfinished attack, plus repeated balance-refused west commands retained as pending movements. Continue the authorized autobasher/workspace/XML fixes and GitHub delivery.

## Behavior

- `dem.balances.rejectAction(action)` retires only the current unacknowledged attack (`lost` is false), never changes balance/equilibrium readiness or identity, and cancels its watchdog. Accepted attack cycles remain immutable and wait for real recovery.
- `dem.hunt.onAttackRejected(reason)` handles explicit divine-grace refusal, stops Hunt with the reason, and rejects that unexecuted action. Do not send RENOUNCE GRACE or retry automatically; after the user removes grace and real readiness returns, explicit Hunt restart works.
- Balance/equilibrium-unavailable triggers call `dem.onBalanceUnavailable(kind)`. Capture whether an unacknowledged attack exists, mark readiness unavailable, then reject a movement only when command attribution is supported.
- `dem.room.onMovementBlocked()` consumes the oldest outstanding unentered hinted movement using existing WrongDir reconciliation, only when the last submitted packet contains standard movement commands exclusively and no earlier command response remains ambiguous. Sequence each submitted segment so an older movement acknowledgement cannot clear a newer nonmovement command. Known room observations (`look`, `l`, `ih`) cannot own balance refusals. Tracked attack execution requires positive server balance-loss evidence, not repeated unavailable text. Reset attribution on connection/death reset. Each attributable refusal retires one failed attempt; real successful moves, unresolved unhinted arrivals, and later queued commands remain pending normally.
- Preserve room/heading proof, timers, cooldown ownership, targeting/pending APIs, areas, Duality, &&, curing ownership. Restore no readiness from refusal or clocks.

## Work

- [x] Reproduce both logs with behavioral regressions, including ambiguity and accepted-action preservation.
- [x] Implement runtime + trigger/docs/version0.1.6 metadata, preserving original creation timestamp/layout and local mapper reference.
- [x] Rebuild XML and run full behavioral, deterministic-build, source parity, alias/trigger, metadata and Lua syntax checks.
- [x] Independent review and material findings fixed RED to GREEN; verified changes ready for authorized commit/push and remote comparison.

Live acceptance: grace refusal followed by manual renunciation and successful explicit restart; repeated balance-refused movement followed by one successful move without phantom pending tokens. Untagged response attribution retains the existing ordered-stream assumption; ambiguous refusals do not discard commands.

## Verification record

Actual pre-change embedded XML produced 155 passing and 12 failing behavioral cases. Runtime integration then passed 167 cases; the rebuilt XML also passes all 167, including actual Grace/balance/equilibrium trigger bodies, deterministic builds, seven-module source parity, original folder layout/timestamp and 0.1.6 metadata, alias/trigger contracts, Lua compilation, and whitespace checks. Independent review follows.

Independent review found two Important issues: later pure movement packets overwrote earlier response ambiguity, and a new hinted move discarded an unresolved successful unhinted arrival. Seven regressions reproduced five failures (169 passed, five failed). Both findings were fixed in one root pass: command sequences retain ambiguity until positively acknowledged past, accepted execution is separate from unavailable text, and unresolved arrival identity gaps survive later refused moves. The rebuilt embedded XML passes all 174 cases and the complete synchronization, deterministic-build, layout, metadata, alias/trigger, and Lua syntax suite.

Review rulings: no Critical or Minor findings. Arbitrarily reordered responses remain outside the documented ordered-stream assumption. Multiple unavailable messages for one command were not established by captured logs, but the regression now prevents them from manufacturing execution evidence. Live game ordering and acceptance remain unverified; the mapper reference remains local and untouched. No second reviewer pass is required after the root fix pass.
