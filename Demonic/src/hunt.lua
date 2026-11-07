dem.hunt = {enabled = false, reason = 'Disabled.'}
local hunt = dem.hunt
local selected, manualReference, stateWaiting, waitingGeneration, watchedAction
local submittedByName, submittedById, submittedAny = {}, {}, false

function hunt.resetTerminalHistory()
  submittedByName, submittedById, submittedAny = {}, {}, false
end

local function rememberName(action, name)
  if type(name) ~= 'string' or dem.norm(name) == '' then return false end
  name = dem.norm(name)
  local previous = submittedByName[name]
  local older = previous and previous.action
  local ambiguous = previous and (previous.ambiguous or (older ~= action
    and (older.retired or older.key ~= action.key or older.generation ~= action.generation))) or false
  submittedByName[name] = {action = action, ambiguous = ambiguous}
  action.names = action.names or {}
  action.names[name] = true
  return ambiguous
end

function hunt.onObserved(key, item)
  local action = submittedById[dem.room.generation .. ':' .. key]
  if action and type(item) == 'table' then rememberName(action, item.name) end
end

local function message(text) dem.message(text) end
local function schedule() if dem.schedule then dem.schedule() end end
local function cancelState()
  stateWaiting = false
  waitingGeneration = nil
  dem.cancel('state-watchdog')
end
local function waitForState(reason)
  hunt.reason = reason or 'Waiting for room or character data.'
  local generation = dem.room.generation
  if stateWaiting and waitingGeneration == generation then return end
  stateWaiting = true
  waitingGeneration = generation
  dem.defer('state-watchdog', 10, function()
    if hunt.enabled and stateWaiting and waitingGeneration == generation then
      if not dem.room.num then hunt.stop('Room identity was not confirmed after GMCP and ih recovery.')
      elseif not dem.room.ready then hunt.stop('A full room roster did not arrive after GMCP and ih recovery.')
      else hunt.stop('Required character data did not arrive.') end
    end
  end)
end
local function watchAction(action)
  if watchedAction == action then return end
  watchedAction = action
  local elapsed = math.max(0, dem.now() - (action.started or dem.now()))
  dem.defer('attack-watchdog', math.max(0, 10 - elapsed), function()
    if hunt.enabled and dem.balances.action == action then
      hunt.stop('The last action has not completed a confirmed balance cycle.')
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
  if dem.room.cancelRefresh then dem.room.cancelRefresh() end
  hunt.reason = reason or 'Disabled by user.'
  cancelState()
  dem.cancel('attack-watchdog')
  watchedAction, selected, manualReference = nil, nil, nil
  clearOwned()
  if wasEnabled then message('Hunt mode off' .. (reason and ': ' .. reason or '.')) end
  if wasEnabled and dem.defences and dem.defences.enabled then schedule() end
end

function hunt.onAttackRejected(reason)
  local action = dem.balances.action
  if action and (action == hunt.lastAction or action.kind == 'shield') and dem.balances.rejectAction(action) then
    if action == hunt.lastAction then hunt.lastAction = nil end
  end
  hunt.stop(reason or 'The submitted attack was refused.')
end

function hunt.toggle()
  if hunt.enabled then hunt.stop(); return false end
  if dem.balances.dead then
    hunt.stop('You are dead.')
    message('Hunt mode remains off while you are dead.')
    return false
  end
  if dem.targeting.kind == 'player' then dem.targeting.clear('hunt') end
  manualReference = dem.targeting.kind == 'denizen' and dem.targeting.source == 'manual' and dem.target or nil
  selected, hunt.enabled = nil, true
  dem.room.subscribe()
  dem.room.request('Hunt mode enabled')
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
  if kind == 'pending' then
    manualReference = nil
    waitForState('Waiting to identify the selected target.')
    schedule()
    return
  end
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
  if b.dead then hunt.stop('You are dead.'); return end
  local shielding = v and finite(v.hp) and finite(v.maxhp) and v.maxhp > 0
    and v.hp > 0 and v.hp / v.maxhp * 100 <= 40
  -- A known low percentage stops immediately, even while another field is missing.
  if not shielding and v and finite(v.hp) and finite(v.maxhp) and v.maxhp > 0 and v.hp / v.maxhp * 100 <= dem.settings.hpLimit then
    hunt.stop('Health reached the configured limit.'); return
  end
  if v and finite(v.mp) and finite(v.maxmp) and v.maxmp > 0 and v.mp / v.maxmp * 100 <= dem.settings.manaLimit then
    hunt.stop('Mana reached the configured limit.'); return
  end
  if shielding then
    if not knownVitals() or b.bal == nil or b.eq == nil or v.prone == nil or v.stunned == nil then
      waitForState('Waiting for character data to shield.'); return
    end
    cancelState()
    if b.action then hunt.reason = 'Shielding: waiting for the current action recovery.'; watchAction(b.action); return end
    watchedAction = nil
    if not b.bal or not b.eq or v.prone or v.stunned then
      hunt.reason = 'Shielding: waiting for balance, equilibrium, standing and unstunned status.'; return
    end
    local cost = dem.ritualism.manaCost({'inversion', 'hammer'})
    if not cost or v.mp < cost then hunt.reason = 'Shielding: waiting for 18 mana.'; return end
    local command, err = dem.ritualism.buildTrace({'inversion', 'hammer'}, 'me')
    if not command then hunt.stop(err); return end
    local action = {kind = 'shield', started = dem.now()}
    if not b.beginAction(action) then return end
    hunt.reason = 'Shielding: waiting for confirmed balance recovery.'
    watchAction(action)
    send(command)
    return
  end
  if dem.targeting.kind == 'pending' then
    waitForState('Waiting to identify the selected target.'); return
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
  local action = {kind = 'attack', reference = dem.target, key = candidate.key, room = room.num, generation = room.generation,
    item = candidate.item, retired = false, started = dem.now()}
  if not b.beginAction(action) then return end
  local name = dem.norm(candidate.item.name)
  -- Text has no ID. Once another physical target could own the same name,
  -- defer that ambiguous text to GMCP rather than retiring its successor.
  action.ambiguousKill = rememberName(action, name)
  action.ambiguousMissing = submittedAny
  submittedAny = true
  submittedById[room.generation .. ':' .. action.key] = action
  hunt.lastAction = action
  hunt.reason = 'Waiting for the confirmed attack balance cycle.'
  watchAction(action)
  send(command)
end

local function belongsToRoom(action)
  return action and action.room == dem.room.num and action.generation == dem.room.generation
end

local function reconcile(action)
  if not hunt.enabled or not belongsToRoom(action) or action.refreshRequested then return end
  -- A proved retirement owns one reconciliation. Ambiguous text may describe
  -- an older target; a later real terminal event still needs a fresh query.
  if action.retired then action.refreshRequested = true end
  -- An authoritative full snapshot already reconciles its own missing items.
  if dem.room.processingList then return end
  dem.room.request('Submitted target left or died', false)
  schedule()
end

local function retire(action)
  if not action then return end
  if not action.retired then
    action.retired = true
    if belongsToRoom(action) then
      dem.room.retired[action.key] = true
      dem.room.items[action.key] = nil
      for i = #dem.room.order, 1, -1 do
        if dem.room.order[i] == action.key then table.remove(dem.room.order, i) end
      end
      -- Lifecycle messages belong to the immutable submitted action, never to a
      -- subsequently selected manual target.
      if dem.target == action.reference and selected and selected.key == action.key
          and selected.room == action.room then
        manualReference, selected = nil, nil
        dem.targeting.clear('hunt')
      end
      dem.room.notify()
    end
  end
  -- A preceding GMCP Remove may have retired this action before its kill text.
  reconcile(action)
end

function hunt.onKill(name)
  local action = hunt.lastAction
  local normalized = type(name) == 'string' and dem.norm(name) or nil
  if action and normalized and action.names and action.names[normalized] then
    local provenance = submittedByName[normalized]
    if provenance and provenance.ambiguous and not action.retired then reconcile(action)
    else retire(action) end
  end
end
function hunt.onMissing()
  local action = hunt.lastAction
  if action and action.ambiguousMissing and not action.retired then reconcile(action)
  else retire(action) end
end

function hunt.onRemoved(key)
  local action = hunt.lastAction
  if action and action.key == key and belongsToRoom(action) then
    action.retired = true
    reconcile(action)
  end
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
  if type(raiseEvent) == 'function' then raiseEvent('dem.huntListChanged') end
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
  if type(raiseEvent) == 'function' then raiseEvent('dem.huntListChanged') end
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
function hunt.status(detailed)
  if detailed ~= true then
    message('Hunt mode ' .. (hunt.enabled and 'on' or 'off') .. '; target: '
      .. (dem.target or 'none') .. '; ' .. hunt.reason)
    return hunt.enabled
  end
  local v, b = dem.vitals, dem.balances
  local function value(n) return n ~= nil and tostring(n) or 'unknown' end
  local refresh = dem.room.refresh
  local diagnostics = dem.room.diagnostics and dem.room.diagnostics() or {}
  local age = refresh and string.format('%.1fs', math.max(0, dem.now() - refresh.started)) or 'none'
  local count = 0
  for key, item in pairs(dem.room.items) do
    if not dem.room.retired[key] and dem.room.living(item) then count = count + 1 end
  end
  message('Hunt mode ' .. (hunt.enabled and 'on' or 'off') .. '; area: ' .. (dem.room.area or 'unknown')
    .. '; target: ' .. (dem.target or 'none') .. '; limits: ' .. dem.settings.hpLimit .. '% health, '
    .. dem.settings.manaLimit .. '% mana; HP: ' .. value(v.hp) .. '/' .. value(v.maxhp)
    .. '; MP: ' .. value(v.mp) .. '/' .. value(v.maxmp) .. '; balance: ' .. value(b.bal)
    .. '; equilibrium: ' .. value(b.eq) .. '; refresh: ' .. (dem.room.phase or 'unknown')
    .. '; request age: ' .. age .. '; retry: ' .. tostring(refresh and math.max(0, refresh.attempts - 1) or 0)
    .. '; ih: ' .. (refresh and refresh.ihSent and 'sent' or 'not sent')
    .. '; refresh reason: ' .. (refresh and refresh.reason or 'none')
    .. '; room: ' .. value(dem.room.num) .. '; context: ' .. value(diagnostics.contextId)
    .. '; roster: ' .. tostring(count)
    .. '; refresh mode: ' .. (refresh and (refresh.blocking and 'blocking' or 'background') or 'none')
    .. '; last GMCP room: ' .. value(diagnostics.lastReceivedRoom)
    .. '; refresh error: ' .. (diagnostics.refreshError or 'none')
    .. '; target type: ' .. (dem.targeting.kind or 'none')
    .. (hunt.enabled and '; state: ' or '; last stop: ') .. hunt.reason)
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
