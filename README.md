# Imperian
Diabolist profession

Demonic is a Mudlet package providing shared targeting and area-specific hunting for an Imperian Diabolist. It uses learned Duality to submit one `trace fire ice <target>` command, waits for real balance/equilibrium recovery, and leaves healing to Imperian autocuring.

## Installation and first hunt

1. Download [Demonic.xml](Demonic/Demonic.xml) and import it using Mudlet's Package Manager. The XML contains all runtime code; `src` is for development. When upgrading to 0.1.9, remove the installed Demonic package before importing the rebuilt XML. Keep one active Demonic package and one active **Hunt mode** alias. Your profile's `Demonic-settings.lua` file preserves area lists and thresholds.
2. Enable GMCP in the Imperian connection settings. Set the game command separator to `&&` (`CONFIG SEPARATOR &&`); `dem.separator` uses the same value.
3. Enter an area and add a whole word or full denizen description to its list: `hunt add ant`, `hunt add bat`, or `hunt add a warrior ant`. Single words match whole words in names; longer descriptions match the full name. `hunt list` shows this area's list. New areas start empty.
4. Enter `hunt` to enable hunting and again to stop it. `hunt status` shows the short state, target, and current waiting or stopped reason. `hunt status debug` adds room, roster, readiness, attack, and refresh diagnostics.

Hunting stays enabled while you move manually and waits when no eligible denizens are present. At **40% health or below**, it pauses attacks and uses `trace inversion hammer me` to shield you. It repeats only after confirmed balance recovery and resumes attacks above 40%. Shielding overrides the configured health stop while the mana stop still applies; it requires 18 mana. It preserves your hunting target and waits for any pending action before casting. It does not move you, sip, or cure.

## Class defence maintenance

Enter `ddef` to toggle maintenance. The **Defs** alias is under **Aliases → Demonic → Diabolist → Ritualism**, with pattern `^ddef$`. Maintenance works while Hunt is off, pauses when Hunt is on, and resumes when Hunt stops. It starts disabled after reload, reconnect, or death.

The sequence is `summon ouroboros`, `demon armor`, `demon regeneration`, `demon soulmask`, `demon syphon`, `trace vitality me`, then `nightfall`. Summon confirmation comes before any defence; already confirmed active entries are skipped. The class registry and controller are in **Scripts → Diabolist → Malignosis → Diabolist defences**, with command builders in each skill folder.

Maintenance shares the action gate with Hunt: no overlapping commands, and timers never grant readiness. Vitality requires its activation confirmation and real balance recovery; Nightfall requires confirmation and real equilibrium recovery. Other class commands require their confirmation and a subsequent ready prompt. Nightfall needs 27 mana, Vitality 9; all maintenance respects the configured mana floor. Unknown/stunned/prone/unready character state blocks casting. If a pending command has not completed after ten seconds, maintenance disables and reports why; the unresolved action remains gated until confirmation and recovery, or connection reset.

Triggers track Ouroboros, Armor, Regeneration, Soulmask, Syphon, Vitality, and Nightfall under `dem.defences.active`. Ouroboros banishment invalidates its four dependent defences. `The darkness around you dissipates.` clears Nightfall; its activation line never clears it. Vitality consumption/cooldown and other missing defence-loss messages are not yet supplied, so these losses are not automatically detected. Already-active/refusal responses without a known confirmation can time out; check the game response before restarting maintenance. Use `dem.defences.reason` for the current maintenance diagnostic.

## Room panels

Demonic 0.1.9 includes three independent **Denizens**, **Items**, and **Players** panels. They start in a left-side stack with charcoal backgrounds, crimson borders and violet headings. Drag their title bars to move them and drag their edges to resize them. The title-bar right-click menu provides Mudlet's lock, minimize, and border attachment controls. Each panel's position, size, minimized state and visibility are saved separately in the current profile using names beginning with `Demonic.RoomUI.`.

- `demui show` shows the panels; `demui hide` hides them.
- `demui reset` restores the default visible, unlocked left-side stack.
- Denizens with identical descriptions appear as `an ant x2`. Click/right-click their row for a menu with **Target ID** choices and **Add name to this area's hunt list**. Hunt-listed denizens are gold, the selected group has a violet `[T]` marker, and protected denizens are muted. Targeting while Hunt is off does not start it; selecting a target during Hunt uses its existing attack gates.
- Items show individual IDs with **Get** and **Probe** menu actions. Item names are green and corpses are muted.
- Players appear in cyan, excluding your character when GMCP supplies your name. Their menu selects an explicit player target, which stops Hunt. Full titles appear in the target menu hint. The panel also shows room name, area and room ID.

The lists update from GMCP even with Hunt off. Changing the reported room clears old contents immediately; stale menus cannot act on another room or on removed entries. Waiting for a full snapshot, an empty list, and disconnection have separate displays. The GUI uses Demonic's room roster and needs no Legacy installation or name database. It requests missing room items once through shared GMCP refresh handling while visible; passive GUI use sends no `ih` fallback or retry. Existing active-Hunt recovery budgets remain unchanged. The Players panel waits for a fresh server `Room.Players` snapshot after installation/reset, normally supplied on entering a room; cached player rosters are not reused.

The GUI lives in **Scripts → Demonic → System → GUI** and its aliases in **Aliases → Demonic → System → GUI**. Its API is `dem.ui.show()`, `dem.ui.hide()`, and `dem.ui.resetLayout()`. Colors are centralized in `dem.ui.palette` in the GUI source. Layout changes are saved on reload, uninstall and profile exit. Reload destroys the previous widgets and callbacks; unavailable GUI facilities or rendering/persistence errors leave the autobasher operational.

## Reported rooms and the live roster

The current room is the identity reported by GMCP `Room.Info`. A changed identity clears the previous roster and requires a fresh full `Char.Items.List` for the room before attacking. A room list received before any room identity is ignored; it cannot establish identity. `Char.Items.Add`, `Update`, and `Remove` maintain the known roster by numeric ID after a full list establishes it. Same-room information and background refreshes preserve a usable roster and readiness.

Demonic does not intercept outgoing directions or pause on movement submission. There is a brief accepted window in which the old room's target may still be used until changed `Room.Info` arrives. It does not predict exits, consult a mapper, or use walk text, native room headings, or `Room.WrongDir` to establish a movement barrier or recover an arrival. Room packets are processed as an ordered server stream. Item lists carry no room or request identifier, so arbitrary delayed replies across room changes cannot be assigned reliably; local tests cannot prove live server ordering.

A confirmed kill retires the specific attacked ID. A room removal retires that ID. Hunt can continue with another eligible ID already in the known roster, subject to real balance/equilibrium and attack gates. Kill, removal, and missing-target signals also request a background refresh; they do not clear the remaining known roster or unnecessarily wait for another full list. Duplicate names are distinguished by ID.

Kill and missing-target text do not identify a numeric ID. If an older submitted target could own that message, Hunt requests GMCP reconciliation instead of retiring the successor. This history includes names observed through room lists and updates and survives refused attacks and manual restart. Connection changes, death, and reload reset it.

`dem.room.request(reason, blocking)` defaults to blocking. Requests coalesce within one refresh cycle and share its budgets: immediately send `Char.Items.Room ""`, send `ih` once after 0.2 seconds if still unresolved, retry GMCP once after one second, and finish after ten seconds. Recovery uses only `ih`; it never sends `look` or `ql`. A background timeout with a usable room and roster records a diagnostic and preserves hunting. A blocking timeout while identity or a required roster remains missing stops hunting. Turning Hunt off, disconnecting, or reloading cancels recovery.

## Attacks, resources, and safety

Known server refusals retire the rejected attack without granting balance or equilibrium readiness. `You must regain balance first.` and the equivalent equilibrium refusal mark that resource unavailable. An accepted attack waits for real loss/recovery acknowledgements; timers never grant readiness. An unresolved attack stops hunting after ten seconds.

If the server says `You currently walk in divine grace and may neither be harmed nor harm another.`, Hunt stops and releases the unexecuted attack. Renounce grace manually and enter `hunt` to restart; Demonic never sends `RENOUNCE`. A rejected attempt's watchdog cannot stop a restarted Hunt.

An alive-to-dead transition stops hunting and clears pending targeting, the current attack, room readiness, and refresh state once. Repeated dead packets do not repeat cleanup. Revival never starts hunting; enter `hunt` again after recovering.

Health and mana independently adopt GMCP authority on the first explicit current or maximum field, including malformed values. Adoption clears both text-derived members so units cannot be mixed. That authority persists across prompts and partial updates until connection reset. Invalid data becomes unknown. Prompt resource parsing is a fallback only before that resource adopts GMCP authority. Balance and equilibrium retain their GMCP/text readiness fallback.

## Targets and controls

- `t fido`, `t fido1234`, or `t 1234` selects one unchanged, opaque reference in `dem.target`. Automatic classification waits with `dem.targeting.kind = "pending"` when identity or the required full roster is missing. A living match becomes a denizen target; otherwise it becomes a player target and stops Hunt. Pending selection preserves an existing attack and submits no new one. It also resolves while Hunt is off.
- A generic word such as `t ant` selects the first eligible living match. Hunt pins that denizen's numeric ID across roster reorderings and uses the ID in attack commands; `dem.target` retains the original word. Use a name-plus-ID or numeric ID to select a specific denizen.
- `t clear` stops hunting and clears the target. A replacement target, clear, changed reported room, or reconnect cancels the previous pending selection. Outgoing directions do not change the reported room context.
- Manually selecting a denizen while Hunt is active switches the next attack to it, even if it is absent from the area list. This exception lasts for that target only; later automatic selection uses the list. Dead/protected entries remain excluded. Manual targeting while Hunt is off never starts it. Hunt never attacks a player target.
- `hunt remove <word or full description>` removes an entry from this area's list. Names ignore case and repeated whitespace.
- `hunt limits 30 10` changes the health and mana stop percentages. Defaults are 30% HP and 10% mana. The mana limit stops Hunt; enter `hunt` after recovery. Emergency shielding takes priority over the health stop at or below 40%; a configured health stop above 40% still applies outside the shielding range. Both combined traces require at least 18 mana.

Area lists and thresholds are saved in `Demonic-settings.lua` in the current Mudlet profile. Targets and active hunting are never restored after reconnect or reload.

## System interfaces and layout

The only package global is `dem`. The current reference is `dem.target`; metadata is under `dem.targeting`.

```lua
dem.targeting.set("fido") -- classify from the reported room roster, or wait pending
dem.targeting.setPlayer("Aeden") -- explicit kind, immediate
dem.targeting.setDenizen("fido1234") -- explicit kind, immediate
dem.targeting.get() -- current unchanged reference
dem.targeting.clear()
dem.targeting.resolvePending() -- scheduled before Hunt, even with Hunt off
dem.room.request("Refresh room", false) -- background refresh
dem.ritualism.buildTrace({"fire", "ice"}, "fido1234") -- builds; does not send
dem.joinCommands({"stand", "score"}) -- "stand&&score"
```

`dem.targetChanged` announces `(oldReference, newReference, kind, source)` after the event name. Use targeting functions instead of assigning `dem.target` directly. `source` defaults to `manual`; Hunt uses `hunt` so its updates do not act as manual overrides. `dem.room.contextId` identifies the reported-room context. Explicit `setPlayer` and `setDenizen` select a kind immediately. `dem.roomChanged` announces a reason after accepted room updates, reset, or retirement; `dem.huntListChanged` announces area-list edits. Player records are keyed by lowercase short name in `dem.room.players`, with `playersReady` identifying a received full snapshot; this never changes item-roster readiness.

- **Hunt mode** (`^hunt$`) and helper aliases live in **Aliases → Demonic → System → Autobasher**. **Hunt status** uses `^hunt status(?: (debug))?$`.
- Targeting lives in **Scripts → Demonic → System → Targeting**. Its single alias under **System → Targeting** is exactly `^t (\w+)$` and runs `dem.targeting.set(matches[2])`; `t clear` uses the same dispatcher.
- Balance/equilibrium loss, gain, unavailable, and prompt-readiness triggers live in **Triggers → Demonic → System → Balances**. Unavailable triggers call `dem.onBalanceUnavailable("bal")` or `dem.onBalanceUnavailable("eq")`.
- **Denizen slain**, **Target absent**, and **Grace blocks attack** live in **Triggers → Demonic → System → Autobasher**. The package generates no **Room entered** or **Room heading** triggers.
- Room GMCP handling lives in **System → Api stuff**, the hunt controller in **System → Autobasher**, and trace construction in **Diabolist → Ritualism**.

The XML preserves the exported arrangement: **Diabolist** and **System** are direct roots for triggers and aliases; scripts have **System**, **Diabolist**, and a final standalone **Initialize Demonic** script. Package Manager supplies the **Demonic** wrapper, producing **Demonic → System** without a duplicate inner folder. Group metadata and the exported creation timestamp are preserved.

Duality is configured as learned (`dem.ritualism.duality = true`). It is passive and has no activation command. The builder accepts one or two symbols, rejects more than two, and rejects two when the capability is false. Fire and Ice each cost 9 mana. Reported balance durations are diagnostic.

## Development and verification

With PowerShell and Lua/luac on PATH, run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
```

The build uses `tools/Demonic.template.xml` to preserve folder layout and metadata and bundles readable Lua sources into the XML. Edit sources/template rather than generated XML. Tests check deterministic rebuilds, layout/timestamp preservation, all eleven embedded scripts against their sources, exact targeting/status/GUI/Defs aliases, active refusal/kill trigger contracts, and the absence of movement/heading triggers and outgoing movement interception. They execute the embedded scripts and actual alias/trigger bodies with external Mudlet I/O simulated, test room/roster updates and refresh budgets, and compile all embedded Lua plus `config.lua`. GUI behavior tests use widget doubles to exercise grouping, player updates, colors, callbacks, passive refresh, saved layouts and cleanup. Code uses Lua 5.1-compatible syntax; local verification uses installed Lua 5.4.

Live Imperian acceptance remains separate: verify changed `Room.Info` immediately clears old targets, a full room list restores readiness without a prompt, preidentity lists are ignored, Add/Update/Remove maintain IDs, kill/removal continues through a known roster with duplicate names, background refresh timeouts preserve usable data, blocking refresh timeout stops Hunt, the 0.2-second `ih` fallback and single retry, rapid manual movement under the accepted old-target window, both status forms, pending targeting, refusal recovery, death/revival, resource authority, and a complete fire/ice kill.

Export other Mudlet packages into separate directories so their generated `config.lua` cannot replace Demonic's metadata.

Live GUI acceptance: use a current Mudlet with bundled Geyser/Adjustable widgets; verify dragging/resizing, scrollbars, title-bar menus, independent saved layouts, empty/crowded rooms, player arrivals/departures, popup actions and active-Hunt target switching. These native visual checks and live Imperian ordering are separate from the simulated test suite.
