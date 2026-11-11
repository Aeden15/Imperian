dem.targeting = {kind = nil, source = nil}
local targeting = dem.targeting
local pending

local function change(ref, kind, source)
  source = source or 'manual'
  if kind ~= 'pending' then pending = nil end
  local previous = dem.target
  dem.target = ref
  targeting.kind, targeting.source = kind, source
  -- The scheduler sees selection changes immediately, even between prompts.
  if dem.hunt and type(dem.hunt.onTargetChanged) == 'function' then
    dem.hunt.onTargetChanged(previous, ref, kind, source)
  end
  if type(raiseEvent) == 'function' then raiseEvent('dem.targetChanged', previous, ref, kind, source) end
  return true
end

local function select(ref, kind, source)
  local valid, err = dem.validReference(ref)
  if not valid then dem.message(err); return false, err end
  return change(valid, kind, source)
end

function targeting.setPlayer(ref, source) return select(ref, 'player', source) end
function targeting.setDenizen(ref, source) return select(ref, 'denizen', source) end
function targeting.clear(source) return change(nil, nil, source) end
function targeting.get() return dem.target end

function targeting.denizenId()
  if targeting.kind ~= 'denizen' or not dem.target then return nil end
  local preferred = dem.hunt and dem.hunt.selectedId()
  if preferred then return preferred end
  local item, key = dem.room.identify(dem.target)
  if item then return key end
end

function targeting.set(ref, source)
  local valid, err = dem.validReference(ref)
  if not valid then dem.message(err); return false, err end
  if valid:lower() == 'clear' then return targeting.clear(source) end
  if not dem.room.num or not dem.room.ready then
    local selection = {reference = valid, contextId = dem.room.contextId, source = source or 'manual'}
    pending = selection
    change(valid, 'pending', selection.source)
    -- Synchronous target consumers may replace or clear this selection.
    if pending == selection then
      dem.room.subscribe()
      dem.room.request('Waiting to identify the selected target')
      dem.schedule()
    end
    return true
  end
  if dem.room.identify(valid) then return targeting.setDenizen(valid, source) end
  return targeting.setPlayer(valid, source)
end

function targeting.resolvePending()
  local selection = pending
  if not selection then return false end
  if selection.contextId ~= dem.room.contextId then
    -- Movement cancels the old exception without disabling automatic hunting.
    return targeting.clear('hunt')
  end
  if not dem.room.num or not dem.room.ready then return false end
  if dem.room.identify(selection.reference) then
    return targeting.setDenizen(selection.reference, selection.source)
  end
  return targeting.setPlayer(selection.reference, selection.source)
end
