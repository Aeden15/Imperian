# Imperian
Diabolist profession

Demonic is a Mudlet package providing shared targeting and area-specific hunting for an Imperian Diabolist. It uses the learned Duality passive to submit one `trace fire ice <target>` command, waits for confirmed balance/equilibrium, and leaves healing to Imperian's autocuring.

## Installation and first hunt

1. Download [Demonic.xml](Demonic/Demonic.xml) and import it using Mudlet's Package Manager. The XML contains all runtime code; the `src` directory is for development only. When upgrading to 0.1.1, remove the installed Demonic package first, then import the rebuilt XML. This replaces the old targeting aliases and triggers. Your profile's `Demonic-settings.lua` file persists, including area lists and thresholds.
2. Enable GMCP in your Imperian connection settings, and enter an area you want to hunt. The game command separator should be `&&` (`CONFIG SEPARATOR &&`); `dem.separator` uses the same value.
3. Add a whole word or full room description to this area's list, for example `hunt add ant`, `hunt add bat`, or `hunt add a warrior ant`. Single words match whole words in denizen names; longer descriptions match the full name. Use `hunt list` to review the current area and its list. A new area has an empty list.
4. Enter `hunt` to enable hunting; enter `hunt` again to turn it off. Use `hunt status` to inspect the mode, target, readiness, or reason it is waiting.

Hunting stays enabled while you move manually. It refreshes the room, uses that area's list, and waits when no eligible denizens are present. It does not move you, manage defenses, sip, or cure.

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
- Room GMCP handling lives in **System → Api stuff**; the hunt controller in **System → Autobasher**; trace construction in **Diabolist → Ritualism**.

These paths describe the XML's original inner `Demonic` folder. Package Manager may add a package wrapper also named `Demonic`, so the editor can display `Demonic → Demonic → System`. The original inner folders are preserved.

Duality is configured as learned for this character (`dem.ritualism.duality = true`). It is passive: there is no activation command. The builder accepts one or two symbols, rejects more than two, and rejects two when the capability is false. Fire and Ice each cost 9 mana. Reported balance durations are diagnostic; no timer grants readiness.

## Development and verification

With PowerShell and Lua/luac on PATH, run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
```

The build uses `tools/Demonic.template.xml` to preserve the original folder structure and bundles readable Lua sources into the XML. Edit the sources/template rather than the generated XML. Tests check repeat-build stability, compare every embedded Script with its source, execute the embedded scripts and actual targeting alias/missing-target trigger bodies with external Mudlet I/O simulated, validate alias/trigger contracts and folder placement, and compile all embedded Lua plus `config.lua`. Code uses Lua 5.1-compatible syntax; local verification uses the installed Lua 5.4 runtime.

Live Imperian acceptance remains separate: verify room `Room.Info`/item-list/prompt ordering, the three target forms, and a complete fire/ice kill. Room lists have no room identifier, so synchronization assumes the server processes GMCP requests in stream order. Transitions discard old contents through the next prompt and require a fresh request before attacking. If state or an attack stays unresolved for 10 seconds, hunting turns off with a diagnostic instead of retrying on a timer.
