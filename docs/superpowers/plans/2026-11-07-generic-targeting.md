# Generic Targeting Fix Implementation Plan

**Goal:** Fix generic denizen selection for all areas, replace the target aliases with `Targeting` (`^t (\w+)$`), synchronize the bundled XML, and push the verified fix.

**Approved behavior:** Preserve `dem.target` as the user's unchanged one-word reference; infer living denizens from the known room roster, otherwise select a player and stop hunting. `t clear` uses the same alias. Hunt pins a unique eligible denizen and attacks its numeric ID. Generic area-list words match whole words; full descriptions retain exact normalized matching. Corpses never create ambiguity, protected entries are not attacked. Existing balance, Duality, safety, and area behavior stays intact.

## Tasks

- [x] Write and observe failing regressions for generic groups, non-ant types, corpse/protected exclusions, stable selection, and unified alias dispatch.
- [x] Update shared room lookup and targeting classification; integrate pinned manual selection and whole-word area matching into Hunt.
- [x] Replace the XML aliases and add the two missing-target messages found in the user's combat log. Update package metadata and documentation.
- [x] Verify readable sources match embedded scripts, builds are deterministic, alias/trigger bodies execute correctly, and the complete suite passes.
- [x] Obtain independent code review and fix material findings with regressions.
- Delivery: commit and push the verified tree to Aeden15/Imperian main; confirm the remote SHA matches the local commit.

## Ownership

Parallel workers own room/targeting and build/metadata/docs respectively; root owns hunt integration, Lua regressions, review and publication. Native GMCP records retain their own IDs/names; the shared target remains one opaque string.

## Acceptance

`t ant` may match warrior and worker ants without ambiguity, preserve `dem.target == "ant"`, and repeatedly attack the same chosen numeric ID despite list reordering. The same behavior works for bats and other denizens. After its departure/death, the manual exception ends and automatic selection uses the area's list. Unknown player references stop hunting; target changes and trailing errors cannot bypass the pending balance cycle.

## Verification record

The new behavior produced 14 failures against the previous XML before implementation. The integrated changes passed 57 tests. Independent review then identified manual exceptions migrating to a second match on dead/protected/renamed updates; three persisted regressions reproduced that failure before the fix. Final result: 60 behavioral tests pass, with deterministic builds, exact source/XML parity for all seven modules, alias/trigger contract checks, and Lua compilation. Live gameplay remains a separate acceptance check.
