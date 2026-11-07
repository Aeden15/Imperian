# Imperian
Diabolist profession

Demonic is a Mudlet package providing shared targeting and area-specific hunting for an Imperian Diabolist. It uses the learned Duality passive to submit one `trace fire ice <target>` command, waits for confirmed balance/equilibrium, and leaves healing to Imperian's autocuring.

## Installation and first hunt

1. Download [Demonic.xml](Demonic/Demonic.xml) and import it using Mudlet's Package Manager. The XML contains all runtime code; the `src` directory is for development only. When upgrading to 0.1.3, remove the installed Demonic package first, then import the rebuilt XML. Keep one active Demonic package and one active **Hunt mode** alias so an older copy cannot also handle `hunt`. Your profile's `Demonic-settings.lua` file persists, including area lists and thresholds.
2. Enable GMCP in your Imperian connection settings, and enter an area you want to hunt. The game command separator should be `&&` (`CONFIG SEPARATOR &&`); `dem.separator` uses the same value.
3. Add a whole word or full room description to this area's list, for example `hunt add ant`, `hunt add bat`, or `hunt add a warrior ant`. Single words match whole words in denizen names; longer descriptions match the full name. Use `hunt list` to review the current area and its list. A new area has an empty list.
4. Enter `hunt` to enable hunting; enter `hunt` again to turn it off. Use `hunt status` for a short on/off state, current target, and waiting or stopped reason. Use `hunt status debug` for full readiness and refresh diagnostics.

Hunting stays enabled while you move manually. It refreshes the room, uses that area's list, and waits when no eligible denizens are present. It does not move you, manage defenses, sip, or cure.

While hunting is active, a new `Room.Info` identity immediately requests a complete room roster with `Char.Items.Room ""`; it does not wait for another prompt. The `You walk <direction>.` trigger also starts that refresh cycle immediately for supported directions, while room identity and roster confirmation still gate attacks. If a complete roster is still missing after 0.2 seconds, it sends `ih` once. An unresolved request retries GMCP once after one second. If reconciliation is still unresolved after ten seconds, hunting turns off with a diagnostic. Recovery never sends `look`, and turning hunting off, disconnecting, or reloading cancels it.

Sending a standard movement command makes the previous room's targets ineligible immediately. The walk trigger supports north, northeast, east, southeast, south, southwest, west, northwest, up, down, in, and out. A confirmed failed move reconciles the last known room. A room roster cannot establish an unknown room identity; attacks wait for both a confirmed identity and a complete roster. A kill starts the same immediate GMCP/0.2-second `ih` cycle; kill, removal, and missing-target signals share one refresh. The existing balance/equilibrium and action cooldown gates still control the next attack. `hunt status debug` includes the refresh phase, request age, retry count, and whether the `ih` fallback has been sent.

## Targets and controls

- `t fido`, `t fido1234`, or `t 1234` selects **one unchanged target string** in `dem.target`. A known living room denizen becomes a denizen target; other references become player targets and turn hunting off. The basher never attacks a player target.
- A generic denizen word such as `t ant` selects the first eligible living match in the room roster. Hunt pins that denizen's numeric ID across roster reorderings and uses the ID in commands, while `dem.target` keeps your original word. Use a name-plus-ID or numeric ID to choose a specific denizen.
- `t clear` turns hunting off and clears the target.
- Manually targeting a denizen while hunting switches the **next** attack to it, including when it is absent from the area list. That exception lasts for this target only; subsequent automatic selection uses the area list. Dead/protected entries remain excluded. Manual selection while hunting is off never turns it on.
- `hunt remove <word or full description>` removes an entry from this area's list. Name comparisons ignore case and repeated whitespace.
- `hunt limits 30 10` sets the health and mana stop percentages. Defaults are 30% HP and 10% mana. Reaching either turns hunting off; type `hunt` again after recovery. The combined attack also requires at least 18 mana.

Area lists and thresholds are saved in `Demonic-settings.lua` inside the current Mudlet profile. Targets and active hunting are never restored after reconnect or package reload.

## System interfaces and layout

The only package global is `dem`. The current reference is `dem.target`; metadata is under `dem.targeting`. Shared functions include:

```lua
dem.targeting.set("fido") -- infer living room denizen or player; "clear" clears
dem.targeting.setPlayer("Aeden")
dem.targeting.setDenizen("fido1234")
dem.targeting.get() -- "fido1234"
dem.targeting.clear()
dem.ritualism.buildTrace({"fire", "ice"}, "fido1234") -- builds; does not send
dem.joinCommands({"stand", "look"}) -- "stand&&look"
```

`dem.targetChanged` announces `(oldReference, newReference, kind, source)` after the event name. System consumers should use the targeting functions, rather than assigning `dem.target` directly. `source` defaults to `manual`; Hunt mode uses `hunt` so its own updates do not behave like manual overrides.

`setPlayer` and `setDenizen` remain available for scripts that need an explicit target kind. The single user-facing **Targeting** alias is exactly `^t (\w+)$`, running `dem.targeting.set(matches[2])`; `t clear` uses that same dispatcher.

- The **Hunt mode** alias (`^hunt$`) and helper aliases live in **Aliases → Demonic → System → Autobasher**.
- Targeting lives in **Scripts → Demonic → System → Targeting**, with its aliases under **System → Targeting**.
- Balance/equilibrium loss, gain, and prompt-readiness triggers live in **Triggers → Demonic → System → Balances**.
- The **Room entered** trigger (`^You walk (\w+)\.$`) lives in **Triggers → Demonic → System → Autobasher** and runs `dem.room.onEntered(matches[2])`. **Hunt status** uses `^hunt status(?: (debug))?$` to select concise or detailed output.
- Room GMCP handling lives in **System → Api stuff**; the hunt controller in **System → Autobasher**; trace construction in **Diabolist → Ritualism**.

The XML preserves the newer exported layout: **Diabolist** and **System** are direct roots for triggers and aliases; scripts have **System**, **Diabolist**, and a final standalone **Initialize Demonic** script. Package Manager adds the **Demonic** wrapper on import, so the editor displays **Demonic → System** without a duplicate inner **Demonic** folder. Group metadata and the exported creation timestamp are preserved.

Duality is configured as learned for this character (`dem.ritualism.duality = true`). It is passive: there is no activation command. The builder accepts one or two symbols, rejects more than two, and rejects two when the capability is false. Fire and Ice each cost 9 mana. Reported balance durations are diagnostic; no timer grants readiness.

## Development and verification

With PowerShell and Lua/luac on PATH, run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
```

The build uses `tools/Demonic.template.xml` to preserve the exported folder structure and metadata and bundles readable Lua sources into the XML. Edit the sources/template rather than the generated XML. Tests check repeat-build stability, preservation of the exported layout and creation timestamp, all seven embedded Scripts against their sources, and the active Hunt/Targeting/status alias and Room entered trigger contracts. They execute embedded scripts and the actual targeting/status alias and room-entry/missing-target trigger bodies with external Mudlet I/O simulated, exercise refresh timing and cancellation, and compile all embedded Lua plus `config.lua`. Code uses Lua 5.1-compatible syntax; local verification uses the installed Lua 5.4 runtime.

Live Imperian acceptance remains separate: verify walk-trigger entry and `Room.Info`/item-list ordering with no following prompt, rapid movement, failed movement, the 0.2-second `ih` fallback, kill continuation, both status forms, the three target forms, and a complete fire/ice kill. Repeated same-room info from `look` does not confirm a queued move; a genuine identity transition or `Room.WrongDir` is required. Room lists have no room or request identifier, so synchronization assumes the server processes GMCP requests in stream order; local tests cannot prove that live ordering. An unresolved attack also stops hunting after ten seconds.

For movement without an outgoing command hint, a genuine identity transition can pair with its walk text until the next prompt. That prompt only closes text correlation and never delays room readiness. Initial identity and failed-movement snapshots cannot absorb a later walk. After an arrival has both identity and contents, another walk refreshes even when the direction repeats. Identical untracked walk messages before either confirmation cannot distinguish duplicates from separate moves; arbitrary walk text delayed across later arrivals is outside the ordering assumption.
