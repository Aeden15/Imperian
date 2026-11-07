-- Room packets are an ordered stream. A movement prompt barrier discards the
-- preceding room's queued packets; GMCP has no generation tag for arbitrary
-- delayed, untagged replies, so the package cannot identify those by room ID.
dem.room = {items = {}, order = {}, retired = {}, ready = false, phase = 'barrier'}
local room = dem.room

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

function room.eligible(item)
  if type(item) ~= 'table' or not id(item.id) or type(item.name) ~= 'string' then return false end
  local attr = type(item.attrib) == 'string' and item.attrib:lower() or ''
  return attr:find('m', 1, true) ~= nil and not attr:find('d', 1, true)
    and not attr:find('x', 1, true)
end

function room.reset()
  room.num, room.area = nil, nil
  room.items, room.order, room.retired = {}, {}, {}
  room.ready, room.phase, room.subscribed = false, 'barrier', false
end

function room.subscribe()
  if room.subscribed then return end
  room.subscribed = true
  if type(sendGMCP) == 'function' then
    sendGMCP('Core.Supports.Add ["Char 1","Char.Items 1","Room 1"]')
  end
end

function room.request()
  if not room.num then return false end
  -- Never bypass the first actual prompt after a movement packet.
  if room.phase == 'barrier' then room.ready = false; return false end
  room.ready, room.phase = false, 'waiting'
  if type(sendGMCP) == 'function' then sendGMCP('Char.Items.Room') end
  return true
end

function room.onInfo(payload)
  if type(payload) ~= 'table' then return end
  local number = id(payload.num)
  if not number then return end
  if number ~= room.num then
    room.num = number
    room.area = type(payload.area) == 'string' and payload.area or nil
    if dem.trim(room.area) == '' then room.area = nil end
    room.items, room.order, room.retired = {}, {}, {}
    room.ready, room.phase = false, 'barrier'
    if dem.hunt then dem.hunt.onRoomChanged() end
  elseif payload.area ~= nil then
    room.area = type(payload.area) == 'string' and payload.area or nil
    if dem.trim(room.area) == '' then room.area = nil end
  end
  changed()
end

function room.onPrompt()
  if room.num and room.phase == 'barrier' then
    room.phase = 'waiting'
    room.request()
  end
end

function room.onList(payload)
  if not room.num or room.phase == 'barrier' or type(payload) ~= 'table'
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
  room.items, room.order, room.ready, room.phase = items, order, true, 'ready'
  for key in pairs(old) do
    if not items[key] then
      room.retired[key] = true
      if dem.hunt then dem.hunt.onRemoved(key) end
    end
  end
  changed()
end

local function delta(payload, liveAdd)
  if not room.num or room.phase == 'barrier' or type(payload) ~= 'table'
      or payload.location ~= 'room' then return end
  local value = payload.item
  local key = type(value) == 'table' and id(value.id) or nil
  if not key then return end
  local item = record(value, room.items[key])
  if not item then return end
  if not room.items[key] then room.order[#room.order + 1] = key end
  room.items[key] = item
  if liveAdd then room.retired[key] = nil end
  changed()
end

function room.onAdd(payload) delta(payload, true) end
function room.onUpdate(payload) delta(payload, false) end

function room.onRemove(payload)
  if not room.num or room.phase == 'barrier' or type(payload) ~= 'table'
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
function room.identify(reference)
  if not room.num or room.phase == 'barrier' then return nil, 'The room identity is not ready.' end
  local valid = dem.validReference(reference)
  if not valid then return nil, 'Invalid denizen reference.' end
  local ref, found, foundKey = valid:lower(), nil, nil
  for _, key in ipairs(room.order) do
    local item = room.items[key]
    if item and not room.retired[key] then
      local matches = ref == key
      if type(item.name) == 'string' then
        for word in item.name:lower():gmatch('[%w]+') do
          if word ~= 'a' and word ~= 'an' and word ~= 'the' then
            if ref == word or ref == word .. key then matches = true end
          end
        end
      end
      if matches then
        if foundKey and foundKey ~= key then return nil, 'That denizen reference is ambiguous.' end
        found, foundKey = item, key
      end
    end
  end
  if not found then return nil, 'That denizen is not in the current room.' end
  return found, foundKey
end

function room.resolve(reference)
  if not room.ready then return nil, 'The room roster is not ready.' end
  return room.identify(reference)
end
