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
Flexible walk prefixes confirm supported directions. Native room headings paired with newly received GMCP identity
can recover a completed movement prefix; later movement still blocks. Cached exits never permanently veto proof.
Death stops hunting and clears movement, pending targets, attacks, and readiness once; revival never starts hunting.
GMCP health and mana authority begins on any explicit field and persists across prompts until connection reset.
Known refusals retire rejected attempts without granting readiness; accepted attacks wait for real balance recovery.
Divine grace refusal stops Hunt; renounce grace manually before enabling Hunt again.

Uses learned Duality for a single `trace fire ice <target>` command. The shared command separator is `&&`.
Default safety stops: 30% health and 10% mana; `hunt limits <hp%> <mana%>` changes them.
Healing is left to Imperian autocuring. GMCP must be enabled. No movement or auto-updating.

Source and usage: https://github.com/Aeden15/Imperian]]
version = [[0.1.6]]
created = "2026-11-07T01:33:06-06:00"
