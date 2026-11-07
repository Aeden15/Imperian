mpackage = [[Demonic]]
description = [[Shared targeting and area-specific Diabolist hunting for Imperian.

`hunt` toggles hunting. `hunt add <word or full description>` adds to the current area's allowlist.
`t <reference>` waits for confirmed room identity and a fresh full roster before automatic classification.
Pending targets keep the opaque reference and submit no new attack; an existing attack is preserved.
A living match selects a denizen; otherwise player classification stops hunting. Explicit target APIs are immediate.
References stay one word: `fido`, `fido1234`, or `1234`. `t clear` stops and clears the target.
Hunt resolves denizens to their numeric IDs for attacks while keeping the shared reference unchanged.
`hunt status` shows a short state and reason; `hunt status debug` shows full diagnostics.
Movement contexts survive prompts and current replies; later movement, replacement, clear, or reconnect cancels pending targeting.
Tracked walk acknowledgements survive prompts. Cached GMCP exits correlate received room info only; identity still needs confirmation.

Uses learned Duality for a single `trace fire ice <target>` command. The shared command separator is `&&`.
Default safety stops: 30% health and 10% mana; `hunt limits <hp%> <mana%>` changes them.
Healing is left to Imperian autocuring. GMCP must be enabled. No movement or auto-updating.

Source and usage: https://github.com/Aeden15/Imperian]]
version = [[0.1.4]]
created = "2026-11-07T01:33:06-06:00"
