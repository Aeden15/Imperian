dem.targeting = {kind = nil, source = nil}
local targeting = dem.targeting

local function change(ref, kind, source)
  source = source or 'manual'
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
