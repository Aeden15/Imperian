# Imperian

Demonic is a Mudlet package for Imperian Summoners. Both hunting modes cast `invoke combustion <denizen ID>` against the selected denizen and wait for server-reported equilibrium recovery between casts. Imperian autocuring handles healing.

## Installation and first hunt

1. Download [Demonic.xml](Demonic/Demonic.xml) and import it using Mudlet's Package Manager. The XML contains all runtime code; `src` is for development. When upgrading to 0.1.13, remove the installed Demonic package before importing the rebuilt XML. Keep one active Demonic package and one active **Hunt mode** alias. Your profile's `Demonic-settings.lua` file preserves area lists and thresholds.
2. Enable GMCP in the Imperian connection settings. Set the game command separator to `&&` (`CONFIG SEPARATOR &&`); `dem.separator` uses the same value.
3. Enter an area and add a whole word or full denizen description to its list: `hunt add ant`, `hunt add bat`, or `hunt add a warrior ant`. Single words match whole words in names; longer descriptions match the full name. `hunt list` shows this area's list. New areas start empty.
4. Enter `hunt` to enable hunting and again to stop it. `hunt status` shows the short state, target, and current waiting or stopped reason. `hunt status debug` adds room, roster, readiness, attack, and refresh diagnostics.

Stationary Hunt waits for eligible denizens as you move. At **40% health or below**, Hunt pauses attacks and exploration movement, then waits for any pending action. It prefers `unleash arctar at me` with at least 18 mana and both cooldowns ready. Arctar requires its shield confirmation and a fresh ready prompt. If Arctar is unavailable, Hunt uses `touch shield`, which requires a shield tattoo and takes equilibrium. Hunt waits while shielded, reassesses protection on confirmed shield loss, and resumes hunting above 40% after the pending action completes.

The server reports the general Unleash cooldown (5 seconds) and Arctar cooldown (40 seconds) separately. Only the corresponding ready message clears each one. An unconfirmed shield attempt stops Hunt after ten seconds. The configured mana limit still applies while shielding.

## Mapped exploration and target health

Enter `hunt explore` to hunt through the current mapped area once. It requires a confirmed GMCP room, that room in Mudlet's loaded map, the map APIs, an unlocked starting room and a nonempty hunt list for the reported area. There is no mapper-package dependency or speedwalking call; Demonic reads Mudlet's map and sends each direction itself. Stop any mapper speedwalk before starting exploration. Enter `hunt` to stop either mode; when Hunt is off, `hunt` starts stationary hunting. `hunt explore` also stops an already active Hunt.

Exploration fights all eligible listed denizens in each room, then requests a fresh full roster to confirm the room is clear. It waits for current action recovery and the existing readiness/resource gates, with emergency shielding taking priority. It selects the nearest reachable unchecked room by number of steps, breaking destination ties by numeric room ID and path ties by alphabetic direction commands. Backtracking rooms are checked again for listed respawns. Empty rooms count as checked; unlisted creatures, protected denizens and corpses do not block departure.

Paths stay inside the starting map area, excluding locked rooms/exits, closed or locked mapped doors, unmapped destinations and special exits. Demonic does not open doors or modify the map. Each movement establishes a barrier before sending one direction: no further combat, shielding or movement until the expected GMCP `Room.Info` and a fresh arrival roster have both been received. A `Room.WrongDir` response, unexpected room, reported area change, concurrent mapper speedwalking or ten-second arrival timeout stops Hunt without retrying the direction. A missing clear-room roster also stops Hunt through the normal refresh timeout. Removing the final hunt-list entry stops exploration.

After all currently reachable rooms have been checked, Hunt stops and reports the checked count; it does not return to the starting room or patrol continuously. Restarting begins a fresh pass. Manual denizen targeting ends exploration and continues stationary Hunt using the existing one-target exception. During an in-flight movement, manual targeting stops Hunt entirely. A player target or `t clear` stops Hunt. Stop, death, disconnect and reload discard exploration state; neither mode starts automatically afterward.

`hunt status` shows the current mode, target health and wait/stop reason. `hunt status debug` adds the visited count, next destination, pending direction and movement reason. Existing `hunt add <name>`, `hunt remove <name>`, `hunt list` and `hunt limits <HP%> <mana%>` control the same area allowlist and thresholds in both modes.

Demonic subscribes to `IRE.Target`, sends `IRE.Target.Set` when the selected physical denizen ID changes, and reads `IRE.Target.Info.hpperc`. The selected Denizens panel row shows `[ID 1234: 75%]`, or `unknown` until valid health arrives. Duplicate-name groups display health for the selected ID only. Health observations stay separate by ID and current room context; room changes, removal, death, reconnect and reload discard old observations. Only packets for the currently requested, present denizen are accepted. `0%` requests roster reconciliation once per zero-health episode; it does not retire an ID, prove a kill or release the movement barrier. Health packets are optional: their absence does not block either hunting mode. Live Imperian health updates and ordered arrival packets still require in-game acceptance.

## Summoner and general defences

Enter `ddef` to run `summon arctar`, `invoke warmth`, `invoke astralvision`, `invoke distortion`, and `touch mindseye` in order. Arctar possession grants physical resistance and is tracked separately from the emergency shield. The Mindseye step requires a Mindseye tattoo. The **Defs** alias lives under **Aliases → Demonic → Summoner**.

The pass advances on a subsequent prompt with fresh balance and equilibrium evidence. The compact `Health:363 Mana:372 (eb)` prompt is sufficient for a manual pass. Hunt pauses the pass, and death, reconnect, or reload cancels it. An unresolved action stops the pass after ten seconds.

Game messages update `dem.defences.active`, including `dem.defences.active.mindseye` for both Mindseye activation and loss. Optional maintenance via `dem.defences.toggle()` casts missing defences when Hunt is off and waits for activation and recovery. Warmth and Astralvision currently have activation messages only. `dem.defences.reason` reports the current diagnostic.

## Room panels

Demonic 0.1.13 includes three independent **Denizens**, **Items**, and **Players** panels. They start in a left-side stack with charcoal backgrounds, crimson borders and violet headings. Drag their title bars to move them and drag their edges to resize them. The title-bar right-click menu provides Mudlet's lock, minimize, and border attachment controls. Each panel's position, size, minimized state and visibility are saved separately in the current profile using names beginning with `Demonic.RoomUI.`.

- `demui show` shows the panels; `demui hide` hides them.
- `demui reset` restores the default visible, unlocked left-side stack.
- Denizens with identical descriptions appear as `an ant x2`. Click/right-click their row for a menu with **Target ID** choices and **Add name to this area's hunt list**. Hunt-listed denizens are gold, the selected group has a violet `[T]` marker, and protected denizens are muted. Targeting while Hunt is off does not start it; selecting a target during Hunt uses its existing attack gates.
- Items show individual IDs with **Get** and **Probe** menu actions. Item names are green and corpses are muted.
- Players appear in cyan, excluding your character when GMCP supplies your name. Their menu selects an explicit player target, which stops Hunt. Full titles appear in the target menu hint. The panel also shows room name, area and room ID.

The lists update from GMCP even with Hunt off. Changing the reported room clears old contents immediately; stale menus cannot act on another room or on removed entries. Waiting for a full snapshot, an empty list, and disconnection have separate displays. The GUI uses Demonic's room roster and needs no Legacy installation or name database. It requests missing room items once through shared GMCP refresh handling while visible; passive GUI use sends no `ih` fallback or retry. Existing active-Hunt recovery budgets remain unchanged. The Players panel waits for a fresh server `Room.Players` snapshot after installation/reset, normally supplied on entering a room; cached player rosters are not reused.

The GUI lives in **Scripts → Demonic → System → GUI** and its aliases in **Aliases → Demonic → System → GUI**. Its API is `dem.ui.show()`, `dem.ui.hide()`, and `dem.ui.resetLayout()`. Colors are centralized in `dem.ui.palette` in the GUI source. Layout changes are saved on reload, uninstall and profile exit. Reload destroys the previous widgets and callbacks; unavailable GUI facilities or rendering/persistence errors leave the autobasher operational.

## Reported rooms and the live roster

The current room is the identity reported by GMCP `Room.Info`. A changed identity clears the previous roster and requires a fresh full `Char.Items.List` for the room before attacking. A room list received before any room identity is ignored; it cannot establish identity. `Char.Items.Add`, `Update`, and `Remove` maintain the known roster by numeric ID after a full list establishes it. Same-room information and background refreshes preserve a usable roster and readiness.

Demonic does not intercept outgoing directions. For manual movement during stationary Hunt, there is a brief accepted window in which the old room's target may still be used until changed `Room.Info` arrives. Exploration's own movements have the stricter barrier described above and validate the map's expected destination against server identity. Walk text and native room headings never establish arrival. Room packets are processed as an ordered server stream. Item lists and target-health packets carry no room or request identifier, so arbitrary delayed replies across room changes cannot be assigned reliably; local tests cannot prove live server ordering.

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
- `hunt limits 30 10` changes the health and mana stop percentages. Defaults are 30% HP and 10% mana. The mana limit stops Hunt; enter `hunt` after recovery. Emergency shielding takes priority over the health stop at or below 40%; a configured health stop above 40% still applies outside the shielding range.

Area lists and thresholds are saved in `Demonic-settings.lua` in the current Mudlet profile. Targets and active hunting are never restored after reconnect or reload.

## System interfaces and layout

The only package global is `dem`. The current reference is `dem.target`; metadata is under `dem.targeting`.

```lua
dem.targeting.set("fido") -- classify from the reported room roster, or wait pending
dem.targeting.setPlayer("Aeden") -- explicit kind, immediate
dem.targeting.setDenizen("fido1234") -- explicit kind, immediate
dem.targeting.get() -- current unchanged reference
dem.targeting.denizenId() -- pinned physical ID, or resolve the current manual reference
dem.targeting.clear()
dem.targeting.resolvePending() -- scheduled before Hunt, even with Hunt off
dem.room.request("Refresh room", false) -- background refresh
dem.defences.active.mindseye -- true, false, or nil until observed
dem.joinCommands({"stand", "score"}) -- "stand&&score"
dem.health.get("1234") -- last observed percentage for this room ID, or nil
dem.hunt.toggle("explore") -- starts a new exploration pass, or stops active Hunt
```

`dem.targetChanged` announces `(oldReference, newReference, kind, source)` after the event name. Use targeting functions instead of assigning `dem.target` directly. `source` defaults to `manual`; Hunt uses `hunt` so its updates do not act as manual overrides. `dem.room.contextId` identifies the reported-room context. Explicit `setPlayer` and `setDenizen` select a kind immediately. `dem.roomChanged` announces a reason after accepted room updates, reset, or retirement; `dem.huntListChanged` announces area-list edits. Player records are keyed by lowercase short name in `dem.room.players`, with `playersReady` identifying a received full snapshot; this never changes item-roster readiness.

- **Hunt mode** (`^hunt$`) and helper aliases live in **Aliases → Demonic → System → Autobasher**. **Hunt status** uses `^hunt status(?: (debug))?$`.
- **Hunt explore** (`^hunt explore$`) calls `dem.hunt.toggle("explore")` in the same folder. `dem.navigation` exposes `active`, `count`, `visited`, `destination`, `pending` and `reason`. `dem.health` exposes `requested`, per-ID `values`, and `get(id)`/`label(id)`; observations and navigation state are never persisted.
- Targeting lives in **Scripts → Demonic → System → Targeting**. Its single alias under **System → Targeting** is exactly `^t (\w+)$` and runs `dem.targeting.set(matches[2])`; `t clear` uses the same dispatcher.
- Balance/equilibrium loss, gain, unavailable, and prompt-readiness triggers live in **Triggers → Demonic → System → Balances**. Unavailable triggers call `dem.onBalanceUnavailable("bal")` or `dem.onBalanceUnavailable("eq")`.
- **Denizen slain**, **Target absent**, and **Grace blocks attack** live in **Triggers → Demonic → System → Autobasher**. The package generates no **Room entered** or **Room heading** triggers.
- Room GMCP handling lives in **System → Api stuff**, the hunt controller in **System → Autobasher**, and shared defence tracking in **System → Defence Controller**.

The XML groups active triggers and aliases under **System** and **Summoner**. It retains the old **Diabolist** folders in a disabled state. **Initialize Demonic** loads after the other scripts. Mudlet supplies the outer **Demonic** folder on import.

Reported balance and equilibrium durations are diagnostic. Combustion uses the configured mana percentage limit while its per-cast mana cost awaits live verification.

## Development and verification

With PowerShell and Lua/luac on PATH, run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
```

The build bundles readable Lua sources into `Demonic.xml` using the folder layout in `tools/Demonic.template.xml`. Edit the sources and template, then rebuild. Tests check deterministic builds, embedded source synchronization, alias and trigger contracts, and the guards on archived Diabolist scripts. They replay Summoner and tattoo defence messages through the generated patterns and handlers. Simulated Mudlet I/O covers roster updates, attack and shield readiness, cooldowns, exploration, selected-ID health, and room panels. The suite also compiles all embedded Lua and `config.lua`. Code uses Lua 5.1-compatible syntax. Local verification uses Lua 5.4.

For live Imperian acceptance, import the rebuilt package and run `ddef`. Check wrapped Arctar possession output and both Mindseye state changes. Hunt an eligible denizen through a complete Combustion kill and record the cast's equilibrium and mana use. Check Arctar shielding, both ready messages, and the tattoo fallback while Arctar is on cooldown. Check that Hunt resumes above 40% after recovery. Exercise ordered room and roster updates, duplicate denizen names, refresh fallback, refusals, and death and revival in the same profile.

Export other Mudlet packages into separate directories so their generated `config.lua` cannot replace Demonic's metadata.

Live GUI acceptance: use a current Mudlet with bundled Geyser/Adjustable widgets; verify dragging/resizing, scrollbars, title-bar menus, independent saved layouts, empty/crowded rooms, player arrivals/departures, popup actions and active-Hunt target switching. These native visual checks and live Imperian ordering are separate from the simulated test suite.
