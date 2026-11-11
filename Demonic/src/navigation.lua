-- Read the Mudlet map, but own every movement and wait for server evidence.
dem.navigation = {active = false, visited = {}, count = 0, reason = 'Disabled.'}
local nav = dem.navigation
local commands = {north='n', northeast='ne', east='e', southeast='se', south='s',
  southwest='sw', west='w', northwest='nw', up='u', down='d', ['in']='in', out='out'}
local clearCheck

local function mapCall(name, ...)
  local fn = _G[name]
  if type(fn) ~= 'function' then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
end

local function mappedArea(key)
  local area = mapCall('getRoomArea', tonumber(key))
  return type(area) == 'number' and area > 0 and area or nil
end

local function hasAllowed()
  for _,yes in pairs(dem.settings.areas[nav.area or dem.room.area] or {}) do
    if yes == true then return true end
  end
  return false
end

function nav.reset(reason)
  dem.cancel('movement-timeout')
  nav.active, nav.pending, nav.destination = false, nil, nil
  nav.visited, nav.count, nav.current, nav.area, nav.mapArea = {}, 0, nil, nil, nil
  nav.reason, clearCheck = reason or 'Disabled.', nil
end

function nav.start()
  nav.reset()
  local room = dem.room
  if not room.num or not room.area then return nil, 'Exploration requires a confirmed room and area.' end
  for _,name in ipairs({'getRoomArea','getRoomExits','roomLocked','hasExitLock','getDoors'}) do
    if type(_G[name]) ~= 'function' then return nil, 'Exploration requires Mudlet map APIs: ' .. name .. '.' end
  end
  local area = mappedArea(room.num)
  if not area then return nil, 'The starting room is not in a loaded mapped area.' end
  if mapCall('roomLocked', tonumber(room.num)) ~= false then return nil, 'The starting mapped room is locked or unavailable.' end
  if not hasAllowed() then return nil, 'Exploration requires a nonempty hunt list for this area.' end
  if mmp and mmp.autowalking then return nil, 'Stop mapper speedwalking before exploring.' end
  nav.active, nav.current, nav.area, nav.mapArea = true, room.num, room.area, area
  nav.reason = 'Waiting to clear the starting room.'
  return true
end

function nav.invalidateClear() clearCheck = nil end

function nav.onInfo()
  if not nav.active then return end
  local room, pending = dem.room, nav.pending
  if room.area ~= nav.area or mappedArea(room.num) ~= nav.mapArea then
    dem.hunt.stop('Exploration stopped: the reported room left the starting area.'); return
  end
  if pending then
    if room.num == pending.to then
      pending.arrived, nav.current = true, room.num
      nav.reason = 'Waiting for the arrival room roster.'
    elseif room.num ~= pending.from then
      dem.hunt.stop('Exploration stopped: unexpected room arrival.')
    end
  elseif room.num ~= nav.current then
    dem.hunt.stop('Exploration stopped: unexpected room change.')
  end
end

function nav.onRoster()
  local pending = nav.pending
  if nav.active and pending and pending.arrived and dem.room.num == pending.to then
    nav.pending = nil
    dem.cancel('movement-timeout')
    nav.reason = 'Checking the arrival room.'
  end
end

function nav.onWrongDir()
  if nav.active and nav.pending then dem.hunt.stop('Exploration stopped: movement was refused.') end
end

function nav.blocked()
  if not nav.active then return false end
  if not hasAllowed() then
    dem.hunt.stop('Exploration stopped: the area hunt list is empty.'); return true
  end
  if mmp and mmp.autowalking then
    dem.hunt.stop('Exploration stopped: mapper speedwalking is active.'); return true
  end
  if nav.pending then
    dem.hunt.reason = nav.reason
    return true
  end
  return false
end

local function edges(key)
  local exits, doors = mapCall('getRoomExits', tonumber(key)), mapCall('getDoors', tonumber(key))
  if type(exits) ~= 'table' or type(doors) ~= 'table' then return nil end
  local result = {}
  for name, destination in pairs(exits) do
    local command = commands[name]
    local number = tonumber(destination)
    local door = doors[name] or (command and doors[command])
    if command and number and number > 0 and number == math.floor(number) then
      local to = tostring(number)
      if to ~= key and mappedArea(to) == nav.mapArea
          and mapCall('roomLocked', number) == false
          and mapCall('hasExitLock', tonumber(key), name) == false
          and (door == nil or door == 1) then
        result[#result+1] = {to=to, command=command}
      end
    end
  end
  table.sort(result, function(a,b) return a.command < b.command end)
  return result
end

local function idLess(a,b)
  if #a ~= #b then return #a < #b end
  return a < b
end

local function nextStep()
  local queue, head = {{key=dem.room.num, depth=0}}, 1
  local seen, foundDepth, candidates = {[dem.room.num]=true}, nil, {}
  while head <= #queue do
    local entry = queue[head]; head = head+1
    if foundDepth and entry.depth > foundDepth then break end
    if not nav.visited[entry.key] then
      foundDepth = entry.depth; candidates[#candidates+1] = entry
    elseif not foundDepth then
      local available = edges(entry.key)
      if not available then return nil, 'Mapped exits could not be read.' end
      for _,edge in ipairs(available) do
        if not seen[edge.to] then
          seen[edge.to] = true
          queue[#queue+1] = {key=edge.to, depth=entry.depth+1,
            first=entry.first or edge}
        end
      end
    end
  end
  table.sort(candidates, function(a,b) return idLess(a.key,b.key) end)
  return candidates[1]
end

-- Called only after combat selection finds no eligible target and all action
-- gates are open. A second full snapshot must confirm every departure.
function nav.onClear()
  if not nav.active or nav.pending then return end
  local room = dem.room
  if not clearCheck or clearCheck.context ~= room.contextId then
    clearCheck = {context=room.contextId, serial=room.snapshotSerial}
    nav.reason = 'Confirming the room is clear.'
    dem.hunt.reason = nav.reason
    room.request(nav.reason, true)
    return
  end
  if room.snapshotSerial <= clearCheck.serial then return end
  if not nav.visited[room.num] then nav.visited[room.num] = true; nav.count = nav.count+1 end
  local step, err = nextStep()
  if not step then
    dem.hunt.stop(err or ('Exploration complete: checked ' .. nav.count .. ' reachable rooms.'))
    return
  end
  local first = step.first
  nav.destination = step.key
  local pending = {from=room.num, to=first.to, direction=first.command, arrived=false}
  nav.pending, clearCheck = pending, nil
  nav.reason = 'Moving ' .. first.command .. '; waiting for room confirmation.'
  dem.hunt.reason = nav.reason
  dem.defer('movement-timeout', 10, function()
    if nav.active and nav.pending == pending then
      dem.hunt.stop('Exploration stopped: arrival identity or roster was not confirmed within ten seconds.')
    end
  end)
  send(first.command)
end
