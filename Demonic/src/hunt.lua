dem.hunt = {enabled = false, reason = 'Disabled.'}
local hunt = dem.hunt
local selected, manualReference, stateWaiting, watchedAction

local function message(text) dem.message(text) end
local function schedule() if dem.schedule then dem.schedule() end end
local function cancelState()
  stateWaiting = false
  dem.cancel('state-watchdog')
end
local function waitForState(reason)
  hunt.reason = reason or 'Waiting for room or character data.'
  if stateWaiting then return end
  stateWaiting = true
  dem.defer('state-watchdog', 10, function()
    if hunt.enabled and stateWaiting then hunt.stop('Required room or character data did not arrive.') end
  end)
end
local function watchAction(action)
  if watchedAction == action then return end
  watchedAction = action
  local elapsed = math.max(0, dem.now() - (action.started or dem.now()))
  dem.defer('attack-watchdog', math.max(0, 10 - elapsed), function()
    if hunt.enabled and dem.balances.action == action then
      hunt.stop('The last attack has not completed a confirmed balance cycle.')
    end
  end)
end
local function clearOwned()
  if dem.targeting.source == 'hunt' then
    dem.targeting.clear('hunt')
  end
end

function hunt.stop(reason)
  local wasEnabled = hunt.enabled
  hunt.enabled = false
  hunt.reason = reason or 'Disabled by user.'
  cancelState()
  dem.cancel('attack-watchdog')
  watchedAction, selected, manualReference = nil, nil, nil
  clearOwned()
  if wasEnabled then message('Hunt mode off' .. (reason and ': ' .. reason or '.')) end
end

function hunt.toggle()
  if hunt.enabled then hunt.stop(); return false end
  if dem.targeting.kind == 'player' then dem.targeting.clear('hunt') end
  manualReference = dem.targeting.kind == 'denizen' and dem.targeting.source == 'manual' and dem.target or nil
  selected, hunt.enabled = nil, true
  dem.room.subscribe()
  dem.room.request()
  waitForState('Waiting for a fresh room roster.')
  message('Hunt mode on.')
  schedule()
  return true
end

function hunt.onRoomChanged()
  selected, manualReference = nil, nil
  if dem.targeting.kind == 'denizen' then dem.targeting.clear('hunt') end
  if hunt.enabled then waitForState('Waiting for the new room roster.') end
end

function hunt.onTargetChanged(oldReference, reference, kind, source)
  if source == 'hunt' or not hunt.enabled then return end
  local preferredKey = selected and selected.room == dem.room.num and selected.key or nil
  selected = nil
  if not reference then hunt.stop('The shared target was cleared.'); return end
  if kind == 'player' then hunt.stop('A player target was selected.'); return end
  manualReference = reference
  -- Retain known same-room ownership even during refresh, so a Remove packet
  -- can end this exception. step() still requires the fresh roster to attack.
  local item, key = dem.room.identify(reference, preferredKey, true)
  if item then
    selected = {reference = reference, key = key, room = dem.room.num, item = item, manual = true}
    if dem.room.ready and not dem.room.eligible(item) then
      hunt.stop('The selected denizen is dead or protected.'); return
    end
  elseif dem.room.ready then
    hunt.stop(key); return
  end
  schedule()
end

local function finite(value)
  return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end
local function knownVitals()
  local v = dem.vitals
  return v and finite(v.hp) and finite(v.maxhp) and v.maxhp > 0 and v.hp >= 0
    and finite(v.mp) and finite(v.maxmp) and v.maxmp > 0 and v.mp >= 0
end
local function areaList()
  return dem.room.area and dem.settings.areas[dem.room.area] or nil
end
local function validateManualSelection()
  local room = dem.room
  if selected and selected.manual and selected.reference == manualReference and selected.room == room.num then
    local item = room.items[selected.key]
    if item and not room.retired[selected.key] and room.living(item) then
      if not room.eligible(item) then hunt.stop('The selected denizen is protected.'); return end
      -- A changed description does not make this a different physical target.
      selected.item = item
      return
    end
    -- The one-target exception ends here, rather than moving to another match
    -- for the same generic word. Automatic selection returns to the area list.
    local reference = manualReference
    selected, manualReference = nil, nil
    if dem.target == reference then dem.targeting.clear('hunt') end
    return
  end
  local item, key = room.resolve(manualReference)
  if not item then hunt.stop(key); return end
  selected = {reference = manualReference, key = key, room = room.num, item = item, manual = true}
end
local function choose()
  local room = dem.room
  -- step() has already validated this exact physical identity, not just its word.
  if manualReference then return selected end
  local allowed = areaList()
  if selected and selected.room == room.num then
    local item = room.items[selected.key]
    if item and not room.retired[selected.key] and room.eligible(item)
        and room.matchesAllowlist(item, allowed) then
      selected.item = item
      return selected
    end
  end
  selected = nil
  if allowed then
    for _, key in ipairs(room.order) do
      local item = room.items[key]
      if item and not room.retired[key] and room.eligible(item) and room.matchesAllowlist(item, allowed) then
        return {reference = key, key = key, room = room.num, item = item, manual = false}
      end
    end
  end
  clearOwned()
  return nil
end

function hunt.step()
  if not hunt.enabled then return end
  local v, b, room = dem.vitals, dem.balances, dem.room
  -- A known low percentage stops immediately, even while another field is missing.
  if v and finite(v.hp) and finite(v.maxhp) and v.maxhp > 0 and v.hp / v.maxhp * 100 <= dem.settings.hpLimit then
    hunt.stop('Health reached the configured limit.'); return
  end
  if v and finite(v.mp) and finite(v.maxmp) and v.maxmp > 0 and v.mp / v.maxmp * 100 <= dem.settings.manaLimit then
    hunt.stop('Mana reached the configured limit.'); return
  end
  if not knownVitals() or not room.ready or not room.num or b.bal == nil or b.eq == nil
      or v.prone == nil or v.stunned == nil then waitForState(); return end
  cancelState()
  if manualReference then
    validateManualSelection()
    if not hunt.enabled then return end
  end
  if b.action then hunt.reason = 'Waiting for the confirmed attack balance cycle.'; watchAction(b.action); return end
  watchedAction = nil
  if not b.bal or not b.eq then hunt.reason = 'Waiting for balance and equilibrium.'; return end
  if v.prone or v.stunned then hunt.reason = 'Waiting until standing and unstunned.'; return end
  local cost = dem.ritualism.manaCost({'fire', 'ice'})
  if not cost or v.mp < cost then hunt.reason = 'Waiting for enough mana for the full attack.'; return end
  local candidate = choose()
  if not candidate then
    if hunt.enabled then hunt.reason = 'No eligible allowed denizens in this room.' end
    return
  end
  if not hunt.enabled then return end
  selected = candidate
  if not candidate.manual and dem.target ~= candidate.reference then
    dem.targeting.setDenizen(candidate.reference, 'hunt')
  end
  -- Target-change callbacks are synchronous; recheck before committing the send.
  if not hunt.enabled or dem.target ~= candidate.reference or b.action then return end
  -- The shared reference stays opaque; attack only the pinned room identity.
  -- Sending a generic word here would let the server switch matching denizens.
  local command, err = dem.ritualism.buildTrace({'fire', 'ice'}, candidate.key)
  if not command then hunt.stop(err or 'Cannot build the hunting attack.'); return end
  local action = {reference = dem.target, key = candidate.key, room = room.num,
    item = candidate.item, retired = false, started = dem.now()}
  if not b.beginAction(action) then return end
  hunt.lastAction = action
  hunt.reason = 'Waiting for the confirmed attack balance cycle.'
  watchAction(action)
  send(command)
end

local function retire(action)
  if not action or action.retired then return end
  action.retired = true
  if action.room ~= dem.room.num then return end
  dem.room.retired[action.key] = true
  -- Lifecycle messages belong to the immutable submitted action, never to a
  -- subsequently selected manual target.
  if dem.target == action.reference and selected and selected.key == action.key
      and selected.room == action.room then
    manualReference, selected = nil, nil
    dem.targeting.clear('hunt')
  end
  if hunt.enabled then dem.room.request(); waitForState(); schedule() end
end

function hunt.onKill(name)
  local action = hunt.lastAction
  if action and type(name) == 'string' and action.item and dem.norm(action.item.name) == dem.norm(name) then retire(action) end
end
function hunt.onMissing() retire(hunt.lastAction) end

function hunt.onRemoved(key)
  local action = hunt.lastAction
  if action and action.key == key and action.room == dem.room.num then action.retired = true end
  if selected and selected.key == key and selected.room == dem.room.num then
    selected, manualReference = nil, nil
    dem.targeting.clear('hunt')
  elseif manualReference and dem.room.ready then
    -- An ID may disappear before the pending manual selection reaches step().
    local item, foundKey = dem.room.resolve(manualReference)
    if item and foundKey == key then manualReference = nil end
  end
  schedule()
end

local function validName(name)
  if type(name) ~= 'string' then return nil end
  name = dem.norm(name)
  if name == '' or name:find('[%c]') then return nil end
  return name
end
local function reject(reason)
  message(reason)
  return nil, reason
end
function hunt.add(name)
  local area = dem.room.area
  if not area then return reject('The current area is unknown.') end
  name = validName(name)
  if not name then return reject('Supply a denizen keyword or full name.') end
  dem.settings.areas[area] = dem.settings.areas[area] or {}
  dem.settings.areas[area][name] = true
  dem.saveSettings()
  message('Added ' .. name .. ' in ' .. area .. '.')
  schedule()
  return true
end
function hunt.remove(name)
  local area = dem.room.area
  if not area then return reject('The current area is unknown.') end
  name = validName(name)
  if not name then return reject('Supply a denizen keyword or full name.') end
  if dem.settings.areas[area] then dem.settings.areas[area][name] = nil end
  dem.saveSettings()
  message('Removed ' .. name .. ' in ' .. area .. '.')
  if selected and not selected.manual and not dem.room.matchesAllowlist(selected.item, areaList()) then
    selected = nil; clearOwned()
  end
  schedule()
  return true
end
function hunt.list()
  if not dem.room.area then message('The current area is unknown.'); return nil end
  local names = {}
  for name, allowed in pairs(areaList() or {}) do if allowed then names[#names + 1] = name end end
  table.sort(names)
  message(dem.room.area .. ': ' .. (#names > 0 and table.concat(names, ', ') or '(no allowed denizens)'))
  return names
end
function hunt.status()
  local v, b = dem.vitals, dem.balances
  local function value(n) return n ~= nil and tostring(n) or 'unknown' end
  message('Hunt mode ' .. (hunt.enabled and 'on' or 'off') .. '; area: ' .. (dem.room.area or 'unknown')
    .. '; target: ' .. (dem.target or 'none') .. '; limits: ' .. dem.settings.hpLimit .. '% health, '
    .. dem.settings.manaLimit .. '% mana; HP: ' .. value(v.hp) .. '/' .. value(v.maxhp)
    .. '; MP: ' .. value(v.mp) .. '/' .. value(v.maxmp) .. '; balance: ' .. value(b.bal)
    .. '; equilibrium: ' .. value(b.eq) .. '; ' .. hunt.reason)
  return hunt.enabled
end
function hunt.setLimits(hp, mana)
  hp, mana = tonumber(hp), tonumber(mana)
  if not finite(hp) or not finite(mana) or hp < 0 or hp > 100 or mana < 0 or mana > 100 then
    return reject('Limits must be percentages between 0 and 100.')
  end
  dem.settings.hpLimit, dem.settings.manaLimit = hp, mana
  dem.saveSettings()
  schedule()
  return true
end
