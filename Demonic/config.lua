mpackage = [[Demonic]]
description = [[Shared targeting and area-specific Diabolist hunting for Imperian.

`hunt` toggles hunting. `hunt add <word or full description>` adds to the current area's allowlist.
`t <reference>` selects a living room denizen or selects a player and stops hunting.
References stay one word: `fido`, `fido1234`, or `1234`. `t clear` stops and clears the target.
Hunt resolves denizens to their numeric IDs for attacks while keeping the shared reference unchanged.

Uses learned Duality for a single `trace fire ice <target>` command. The shared command separator is `&&`.
Default safety stops: 30% health and 10% mana; `hunt limits <hp%> <mana%>` changes them.
Healing is left to Imperian autocuring. GMCP must be enabled. No movement or auto-updating.

Source and usage: https://github.com/Aeden15/Imperian]]
version = [[0.1.1]]
created = "2026-11-06T23:45:11-06:00"
