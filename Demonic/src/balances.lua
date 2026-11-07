dem.vitals = {hp = nil, maxhp = nil, mp = nil, maxmp = nil, stunned = nil, prone = nil}
dem.balances = {bal = nil, eq = nil, action = nil}
local balances = dem.balances

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
    if ready == false then balances.action.lost = true
    elseif ready == true and (explicitRecovery or balances.action.lost) then release() end
  end
end

local function stopIfDead(dead)
  if dead == true or (dem.vitals.hp and dem.vitals.hp <= 0) then
    if dem.hunt and type(dem.hunt.stop) == 'function' then dem.hunt.stop('You are dead.')
    elseif dem.hunt then dem.hunt.enabled = false end
  end
end

function balances.onVitals(payload)
  if type(payload) ~= 'table' then return end
  for _, field in ipairs({'hp', 'maxhp', 'mp', 'maxmp'}) do
    if payload[field] ~= nil then
      local value = number(payload[field])
      dem.vitals[field] = value
      -- Invalid explicit data invalidates knowledge; it does not override text fallback.
      if value ~= nil then dem.runtime.gmcpFields[field] = true end
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
  stopIfDead(boolean(payload.dead))
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

function balances.parsePrompt(text)
  if type(text) ~= 'string' then return end
  local fields = dem.runtime.gmcpFields
  local function vitals(field, value)
    if value and not fields[field] then dem.vitals[field] = number(value) end
  end
  local hp, mp = text:match('Health:%s*(%d+)%s+Mana:%s*(%d+)')
  vitals('hp', hp); vitals('mp', mp)
  local hp2, maxhp, mp2, maxmp = text:match('H:%s*(%d+)%s*/%s*(%d+)%s+M:%s*(%d+)%s*/%s*(%d+)')
  vitals('hp', hp2); vitals('maxhp', maxhp); vitals('mp', mp2); vitals('maxmp', maxmp)
  local eq, bal = text:match('%(([e%-])([b%-])%)')
  if eq and not fields.eq then readiness('eq', eq == 'e') end
  if bal and not fields.bal then readiness('bal', bal == 'b') end
  stopIfDead()
  dem.schedule()
end

function balances.endPrompt() dem.runtime.gmcpFields = {} end

function balances.reset()
  release()
  balances.bal, balances.eq = nil, nil
  balances.balDuration, balances.eqDuration = nil, nil
  dem.vitals = {hp = nil, maxhp = nil, mp = nil, maxmp = nil, stunned = nil, prone = nil}
  dem.runtime.gmcpFields = {}
end
