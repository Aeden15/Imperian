-- Target health is an observation, never evidence that a denizen died.
dem.health = {values = {}, requested = nil}
local health = dem.health
local context, zeroRequested = nil, {}

function health.reset()
  health.values, health.requested, zeroRequested = {}, nil, {}
  context = dem.room.contextId
end

function health.get(key)
  if context ~= dem.room.contextId then return nil end
  return health.values[tostring(key)]
end

function health.label(key)
  local value = health.get(key)
  return value ~= nil and tostring(value) .. '%' or 'unknown'
end

function health.sync(key)
  local room = dem.room
  if context ~= room.contextId then health.reset() end
  for id in pairs(health.values) do
    if room.retired[id] or not room.living(room.items[id]) then
      health.values[id], zeroRequested[id] = nil, nil
    end
  end
  if not key then key = dem.targeting.denizenId() end
  key = key and tostring(key) or nil
  if key and (room.retired[key] or not room.living(room.items[key])) then key = nil end
  if health.requested == key then return end
  health.requested = key
  if key then
    health.values[key], zeroRequested[key] = nil, nil
    room.subscribe()
    if type(sendGMCP) == 'function' then sendGMCP('IRE.Target.Set "' .. key .. '"') end
  end
end

function health.onInfo(payload)
  if type(payload) ~= 'table' or context ~= dem.room.contextId then return end
  local key = tostring(payload.id)
  if key ~= health.requested or dem.room.retired[key]
      or not dem.room.living(dem.room.items[key]) then return end
  local raw = payload.hpperc
  if type(raw) == 'string' then raw = dem.trim(raw):gsub('%%$', '') end
  local value = (type(raw) == 'number' or type(raw) == 'string') and tonumber(raw) or nil
  if not value or value ~= value or value < 0 or value > 100 then value = nil end
  health.values[key] = value
  if value == 0 and not zeroRequested[key] then
    zeroRequested[key] = true
    dem.room.request('Target health reached zero; reconcile roster', false)
  elseif value and value > 0 then zeroRequested[key] = nil end
  if type(raiseEvent) == 'function' then raiseEvent('dem.healthChanged', key, value) end
end

dem.bind('dem.targetChanged', function() health.sync() end)
dem.bind('dem.roomChanged', function() health.sync() end)
