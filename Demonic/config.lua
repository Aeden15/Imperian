mpackage = [[Demonic]]
description = [[Shared targeting and area-specific Diabolist hunting for Imperian.

`hunt` toggles hunting; `hunt add <word or full description>` adds to this area's list.
`t <reference>` classifies against the reported GMCP room and its full roster, or waits pending.
A living match selects a denizen; otherwise player classification stops hunting.
Pending selection submits no new attack and preserves an existing attack. Explicit target APIs are immediate.
References remain one word: `fido`, `fido1234`, or `1234`. `t clear` stops Hunt and clears the target.
Attacks use a pinned numeric denizen ID while the shared reference stays unchanged.
`hunt status` is concise; `hunt status debug` adds roster, readiness, attack, and refresh details.

Room.Info is the only reported identity. A changed room clears the roster and awaits a fresh full list.
Lists before identity are ignored; List/Add/Update/Remove maintain a roster keyed by numeric ID.
Outgoing movement does not pause hunting: a brief old-room target window before changed Info is accepted.
No predicted exits, mapper, walk-text, native-heading, or Room.WrongDir movement barriers are used.
Kills/removals retire the specific ID; Hunt can continue against the known remaining roster.
Background refresh preserves usable readiness. Coalesced requests send GMCP immediately, ih once at 0.2s,
and one GMCP retry at 1s. At 10s a background timeout is diagnostic if usable; missing required identity
or roster stops Hunt. Recovery never sends look or ql. Room packets assume ordered server delivery.

Real balance/equilibrium and attack gates still apply; timers never grant readiness.
Known refusals retire rejected attempts. Divine grace stops Hunt; renounce manually before restarting.
Death stops Hunt and clears pending targeting, attacks, and readiness once; revival never restarts it.
GMCP resource authority persists across prompts and partial updates until connection reset.
Uses learned Duality for one `trace fire ice <target>` command; separator is `&&`.
Default stops: 30% health and 10% mana; `hunt limits <hp%> <mana%>` changes them.
Healing is left to Imperian autocuring. GMCP is required. No movement or auto-updating.
Keep one installed Demonic package and one active Hunt mode alias when upgrading.

Source and usage: https://github.com/Aeden15/Imperian]]
version = [[0.1.7]]
created = "2026-11-07T01:33:06-06:00"
