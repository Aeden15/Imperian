dem.vitals = {hp = nil, maxhp = nil, mp = nil, maxmp = nil, stunned = nil, prone = nil}
dem.balances = {bal = nil, eq = nil, action = nil, dead = false}
local balances = dem.balances
local resourceAuthority = {hp = false, mp = false}

local function number(value)
  local result = tonumber(value)
  if result and result == result and result ~= math.huge and result ~= -math.huge then return result end
end

local function boolean(value)
  if value == true or value == 1 or value == '1' then return true end
  if value == false or value == 0 or value == '0' then return false end
end

local function release()
  balances.action = nil
  dem.cancel('attack-watchdog')
end

local function readiness(kind, ready, explicitRecovery)
  balances[kind] = ready
  if kind == 'bal' and balances.action then
    if ready == false then
      balances.action.lost = true
    elseif ready == true and (explicitRecovery or balances.action.lost) then release() end
  end
end

local function stopIfDead(dead, hpUpdated)
  if dead == true or (dem.vitals.hp and dem.vitals.hp <= 0) then
    if not balances.dead then
      balances.dead = true
      if type(dem.onDeath) == 'function' then dem.onDeath()
      elseif dem.hunt then dem.hunt.stop('You are dead.') end
    elseif dem.hunt and type(dem.hunt.stop) == 'function' and dem.hunt.enabled then
      dem.hunt.stop('You are dead.')
    elseif dem.hunt then dem.hunt.enabled = false end
  elseif dead == false or (hpUpdated and dem.vitals.hp and dem.vitals.hp > 0) then
    balances.dead = false
  end
end

function balances.onVitals(payload)
  if type(payload) ~= 'table' then return end
  for _, pair in ipairs({{'hp', 'maxhp'}, {'mp', 'maxmp'}}) do
    local current, maximum = pair[1], pair[2]
    if payload[current] ~= nil or payload[maximum] ~= nil then
      if not resourceAuthority[current] then
        -- The compact text prompt may use different units. Never combine its
        -- current value or maximum with a newly adopted GMCP resource pair.
        dem.vitals[current], dem.vitals[maximum] = nil, nil
        resourceAuthority[current] = true
      end
      for _, field in ipairs(pair) do
        if payload[field] ~= nil then
          dem.vitals[field] = number(payload[field])
          dem.runtime.gmcpFields[field] = true
        end
      end
    end
  end
  for _, field in ipairs({'stunned', 'prone'}) do
    if payload[field] ~= nil then
      local value = boolean(payload[field])
      dem.vitals[field] = value
      if value ~= nil then dem.runtime.gmcpFields[field] = true end
    end
  end
  for _, kind in ipairs({'bal', 'eq'}) do
    if payload[kind] ~= nil then
      local value = boolean(payload[kind])
      readiness(kind, value)
      if value ~= nil then dem.runtime.gmcpFields[kind] = true end
    end
  end
  stopIfDead(boolean(payload.dead), payload.hp ~= nil)
  dem.schedule()
end

function balances.taken(kind, seconds)
  if kind ~= 'bal' and kind ~= 'eq' then return false end
  readiness(kind, false)
  -- Duration is diagnostic only. A clock cannot confirm recovery.
  balances[kind .. 'Duration'] = number(seconds)
  dem.schedule()
  return true
end

function balances.recovered(kind)
  if kind ~= 'bal' and kind ~= 'eq' then return false end
  readiness(kind, true, true)
  dem.schedule()
  return true
end

function balances.beginAction(action)
  if type(action) ~= 'table' or balances.action then return false end
  action.lost = balances.bal == false
  balances.action = action
  -- Local pessimism gates sends; it is not evidence of a server balance cycle.
  balances.bal = false
  return true
end

function balances.rejectAction(action)
  if not action or balances.action ~= action or action.lost then return false end
  -- A confirmed refusal has no balance cycle to wait for. Leave readiness
  -- exactly as observed; in particular do not undo beginAction's pessimism.
  action.rejected = true
  release()
  return true
end

function balances.parsePrompt(text)
  if type(text) ~= 'string' then return end
  local fields = dem.runtime.gmcpFields
  local hpUpdated = false
  local function vitals(field, value)
    local resource = (field == 'hp' or field == 'maxhp') and 'hp' or 'mp'
    if value and not resourceAuthority[resource] and not fields[field] then
      dem.vitals[field] = number(value)
      if field == 'hp' then hpUpdated = true end
    end
  end
  local hp, mp = text:match('Health:%s*(%d+)%s+Mana:%s*(%d+)')
  vitals('hp', hp); vitals('mp', mp)
  local hp2, maxhp, mp2, maxmp = text:match('H:%s*(%d+)%s*/%s*(%d+)%s+M:%s*(%d+)%s*/%s*(%d+)')
  vitals('hp', hp2); vitals('maxhp', maxhp); vitals('mp', mp2); vitals('maxmp', maxmp)
  local eq, bal = text:match('%(([e%-])([b%-])%)')
  if eq and not fields.eq then readiness('eq', eq == 'e') end
  if bal and not fields.bal then readiness('bal', bal == 'b') end
  stopIfDead(nil, hpUpdated)
  dem.schedule()
end

function balances.endPrompt() dem.runtime.gmcpFields = {} end

function balances.clearForDeath()
  release()
  balances.dead = true
  balances.bal, balances.eq = nil, nil
  balances.balDuration, balances.eqDuration = nil, nil
  dem.vitals.prone, dem.vitals.stunned = nil, nil
end

function balances.reset()
  release()
  balances.dead = false
  resourceAuthority = {hp = false, mp = false}
  balances.bal, balances.eq = nil, nil
  balances.balDuration, balances.eqDuration = nil, nil
  dem.vitals = {hp = nil, maxhp = nil, mp = nil, maxmp = nil, stunned = nil, prone = nil}
  dem.runtime.gmcpFields = {}
end
