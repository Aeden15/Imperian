-- Room.Info owns identity. Item packets form an ordered, untagged stream:
-- a room list can refresh the currently reported room, never establish one.
-- Generations protect local callbacks and submitted target identities.
dem.room = {items = {}, order = {}, retired = {}, ready = false,
  phase = 'unconfirmed', generation = 0, contextId = 0}
local room = dem.room
local lastReceivedRoom, refreshError
local timerKeys = {'room-retry', 'room-fallback', 'room-timeout'}

local function id(value)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  local s = tostring(value)
  if not s:match('^%d+$') then return nil end
  s = s:gsub('^0+', '')
  if s == '' then return nil end
  return s
end

local function record(value, previous)
  if type(value) ~= 'table' then return nil end
  local key = id(value.id)
  if not key then return nil end
  local result = {}
  for k, v in pairs(previous or {}) do result[k] = v end
  for k, v in pairs(value) do result[k] = v end
  result.id = key
  return result, key
end

local function changed()
  if dem.schedule then dem.schedule() end
end

function room.living(item)
  if type(item) ~= 'table' or not id(item.id) or type(item.name) ~= 'string'
      or dem.trim(item.name) == '' then return false end
  local attr = type(item.attrib) == 'string' and item.attrib:lower() or ''
  return attr:find('m', 1, true) ~= nil and not attr:find('d', 1, true)
end

function room.eligible(item)
  return room.living(item) and not item.attrib:lower():find('x', 1, true)
end

local function nameWords(name)
  return name:lower():gmatch('[%w_%-]+')
end

local function keyword(word)
  return word ~= 'a' and word ~= 'an' and word ~= 'the'
end

function room.matchesReference(item, reference)
  if type(item) ~= 'table' or type(item.name) ~= 'string' then return false end
  local key, valid = id(item.id), dem.validReference(reference)
  if not key or not valid then return false end
  local ref = valid:lower()
  if ref == key then return true end
  for word in nameWords(item.name) do
    if keyword(word) and (ref == word or ref == word .. key) then return true end
  end
  return false
end

function room.matchesAllowlist(item, allowed)
  if type(item) ~= 'table' or type(item.name) ~= 'string' or type(allowed) ~= 'table' then return false end
  local name = dem.norm(item.name)
  for entry, enabled in pairs(allowed) do
    if enabled == true and type(entry) == 'string' then
      local normalized = dem.norm(entry)
      if normalized ~= '' then
        if normalized == name then return true end
        if normalized:match('^[%w_%-]+$') and keyword(normalized) then
          for word in nameWords(item.name) do
            if word == normalized then return true end
          end
        end
      end
    end
  end
  return false
end

function room.cancelRefresh()
  for _, key in ipairs(timerKeys) do dem.cancel(key) end
  room.refresh = nil
  if room.ready then room.phase = 'ready' end
end

local function invalidate()
  room.cancelRefresh()
  room.generation = room.generation + 1
  room.num, room.area = nil, nil
  room.items, room.order, room.retired = {}, {}, {}
  room.ready, room.phase = false, 'unconfirmed'
  refreshError = nil
end

function room.reset()
  invalidate()
  room.contextId = room.contextId + 1
  lastReceivedRoom = nil
  room.subscribed, room.processingList = false, false
end

function room.subscribe()
  if room.subscribed then return end
  room.subscribed = true
  if type(sendGMCP) == 'function' then
    sendGMCP('Core.Supports.Add ["Char 1","Char.Items 1","Room 1"]')
  end
end

local function hunting()
  return dem.hunt and dem.hunt.enabled == true
end

function room.request(reason, blocking)
  -- A background query preserves a usable snapshot; it cannot invent one.
  blocking = blocking ~= false or not room.ready or not room.num
  local active = hunting()
  local previous = room.refresh
  if previous and previous.id == room.generation and previous.num == room.num
      and previous.active == active then
    -- A stronger request shares the original retry and timeout deadlines.
    if blocking then
      previous.blocking = true
      room.ready, room.phase = false, room.num and 'waiting' or 'unconfirmed'
    end
    return true
  end
  room.cancelRefresh()
  refreshError = nil
  if blocking then room.ready = false end
  room.phase = room.ready and 'refreshing' or (room.num and 'waiting' or 'unconfirmed')
  local refresh = {id = room.generation, num = room.num, started = dem.now(),
    attempts = 0, ihSent = false, reason = reason or 'Room refresh',
    active = active, blocking = blocking}
  room.refresh = refresh
  local function current()
    return room.refresh == refresh and room.generation == refresh.id
      and room.num == refresh.num and refresh.active and hunting()
  end
  local function query()
    refresh.attempts = refresh.attempts + 1
    if type(sendGMCP) == 'function' then sendGMCP('Char.Items.Room ""') end
  end
  query()
  if active then
    dem.defer('room-fallback', 0.2, function()
      if not current() then return end
      refresh.ihSent = true
      if type(send) == 'function' then send('ih') end
    end)
    dem.defer('room-retry', 1, function() if current() then query() end end)
    dem.defer('room-timeout', 10, function()
      if not current() then return end
      local reason = room.num and 'The full room roster did not arrive.'
        or 'The room identity was not confirmed by Room.Info.'
      refreshError = reason
      room.cancelRefresh()
      if refresh.blocking then
        dem.hunt.stop(reason)
      else
        room.phase = 'ready'
        changed()
      end
    end)
  end
  return true
end

function room.diagnostics()
  return {contextId = room.contextId, lastReceivedRoom = lastReceivedRoom,
    refreshError = refreshError}
end

local function area(value)
  return type(value) == 'string' and dem.trim(value) ~= '' and value or nil
end

function room.onInfo(payload)
  if type(payload) ~= 'table' then return end
  local number = id(payload.num)
  if not number then return end
  lastReceivedRoom = number
  if number ~= room.num then
    -- The first identity is a snapshot, so a pending initial selection keeps
    -- its context. Every actual transition starts a different target context.
    local transition = room.num ~= nil
    invalidate()
    if transition then room.contextId = room.contextId + 1 end
    room.num, room.area, room.phase = number, area(payload.area), 'waiting'
    if dem.hunt then dem.hunt.onRoomChanged() end
    local pendingTarget = dem.targeting and dem.targeting.kind == 'pending'
    if hunting() or pendingTarget then room.request('Room identity confirmed') end
  elseif payload.area ~= nil then
    room.area = area(payload.area)
  end
  changed()
end

function room.onList(payload)
  if not room.num or type(payload) ~= 'table'
      or payload.location ~= 'room' or type(payload.items) ~= 'table' then return end
  local items, order = {}, {}
  for _, value in ipairs(payload.items) do
    local item, key = record(value)
    if item then
      if not items[key] then order[#order + 1] = key end
      items[key] = item
    end
  end
  local old = room.items
  room.cancelRefresh()
  refreshError = nil
  room.items, room.order, room.ready, room.phase = items, order, true, 'ready'
  for key, item in pairs(items) do
    if dem.hunt then dem.hunt.onObserved(key, item) end
  end
  room.processingList = true
  for key in pairs(old) do
    if not items[key] then
      room.retired[key] = true
      if dem.hunt then dem.hunt.onRemoved(key) end
    end
  end
  room.processingList = false
  changed()
end

local function delta(payload, liveAdd)
  if not room.num or type(payload) ~= 'table'
      or payload.location ~= 'room' then return end
  local value = payload.item
  local key = type(value) == 'table' and id(value.id) or nil
  if not key then return end
  local item = record(value, room.items[key])
  if not item then return end
  if not room.items[key] then room.order[#room.order + 1] = key end
  room.items[key] = item
  if liveAdd then room.retired[key] = nil end
  if dem.hunt then dem.hunt.onObserved(key, item) end
  changed()
end

function room.onAdd(payload) delta(payload, true) end
function room.onUpdate(payload) delta(payload, false) end

function room.onRemove(payload)
  if not room.num or type(payload) ~= 'table'
      or payload.location ~= 'room' then return end
  local value = payload.item
  local key = id(type(value) == 'table' and value.id or value)
  if not key then return end
  room.items[key], room.retired[key] = nil, true
  for i = #room.order, 1, -1 do
    if room.order[i] == key then table.remove(room.order, i) end
  end
  if dem.hunt then dem.hunt.onRemoved(key) end
  changed()
end

-- This lookup may use a known same-room snapshot while its refresh is pending.
-- It is for target ownership/removal only; resolve() below gates all attacks.
function room.identify(reference, preferredKey, eligibleOnly)
  if not room.num then return nil, 'The room identity is not ready.' end
  local valid = dem.validReference(reference)
  if not valid then return nil, 'Invalid denizen reference.' end
  local ref, found, foundKey = valid:lower(), nil, nil
  -- A native identity must never redirect to another denizen's numeric name word.
  local exact = room.items[ref]
  if exact or room.retired[ref] then
    if room.retired[ref] or not room.living(exact) then
      return nil, 'That denizen is not in the current room.'
    end
    if eligibleOnly and not room.eligible(exact) then
      return nil, 'That denizen is protected and cannot be hunted.'
    end
    return exact, ref
  end
  local preferred, preferredItem, protected = id(preferredKey), nil, false
  for _, key in ipairs(room.order) do
    local item = room.items[key]
    if item and not room.retired[key] and room.living(item) and room.matchesReference(item, valid) then
      if eligibleOnly and not room.eligible(item) then
        protected = true
      else
        if not found then found, foundKey = item, key end
        if key == preferred then preferredItem = item end
      end
    end
  end
  if preferredItem then return preferredItem, preferred end
  if not found then
    if protected then return nil, 'That denizen is protected and cannot be hunted.' end
    return nil, 'That denizen is not in the current room.'
  end
  return found, foundKey
end

function room.resolve(reference, preferredKey)
  if not room.ready then return nil, 'The room roster is not ready.' end
  return room.identify(reference, preferredKey, true)
end
