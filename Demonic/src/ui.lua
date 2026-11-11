-- The GUI is a view of dem.room, never a second roster or attack controller.
dem.ui = {panels = {}, initialized = false}
local ui, owner, stopped, reported = dem.ui, dem, false, nil
local kinds = {'denizens', 'items', 'players'}
local titles = {denizens = 'Denizens', items = 'Items', players = 'Players'}
local positions = {denizens = '0%', items = '33%', players = '66%'}
ui.palette = {
  background = '#17151e', border = '#87394c', accent = '#b78aef',
  normal = {220, 216, 228}, allowed = {245, 199, 92}, selected = {196, 155, 255},
  players = {103, 220, 235}, items = {132, 211, 156}, muted = {145, 139, 153}
}

local function current() return not stopped and dem == owner end
local function safe(fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    ui.lastError = tostring(result)
    if reported ~= ui.lastError then
      reported = ui.lastError
      pcall(owner.message, 'Room GUI: ' .. ui.lastError)
    end
    return false
  end
  return true, result
end

local function literal(value)
  -- echo/echoPopup display literal text; discard terminal escapes/control bytes.
  return tostring(value or ''):gsub('\27%[[0-?]*[ -/]*[@-~]', ''):gsub('[%c]', ' ')
end

local function write(console, text, color, actions, hints)
  local rgb = ui.palette[color] or ui.palette.normal
  console:setFgColor(rgb[1], rgb[2], rgb[3])
  if actions and #actions > 0 then
    console:echoPopup(literal(text), actions, hints, true)
    console:echo('\n')
  else console:echo(literal(text) .. '\n') end
end

local function visible()
  for _, kind in ipairs(kinds) do
    local panel = ui.panels[kind]
    if panel and not panel.container.hidden then return true end
  end
  return false
end

local function requestMissing()
  if not current() or not ui.initialized or not visible() or not owner.room.num
      or owner.room.ready then return end
  owner.room.subscribe()
  owner.room.request('Room GUI is waiting for room contents', false)
end

local function callback(check, action)
  local context, num = owner.room.contextId, owner.room.num
  return function()
    if not current() or not ui.initialized or owner.room.contextId ~= context
        or owner.room.num ~= num then return end
    safe(function() if check() then action() end end)
  end
end

local function itemNow(key)
  local item = owner.room.items[key]
  if not owner.room.ready or type(item) ~= 'table' or item.id ~= key then return nil end
  return item
end

local function targetAction(key)
  return callback(function()
    return not owner.room.retired[key] and owner.room.eligible(itemNow(key))
  end, function() owner.targeting.setDenizen(key) end)
end

local function idLess(a, b)
  if #a ~= #b then return #a < #b end
  return a < b
end

local function nameLess(a, b)
  local left, right = a.name:lower(), b.name:lower()
  if left == right then return a.name < b.name end
  return left < right
end

local function selectedId()
  return owner.targeting.denizenId()
end

local function denizens(console)
  local byName, groups, count = {}, {}, 0
  local selected = selectedId()
  local allowed = owner.settings.areas[owner.room.area]
  for _, key in ipairs(owner.room.order) do
    local item = owner.room.items[key]
    if owner.room.living(item) and not owner.room.retired[key] then
      local group = byName[item.name]
      if not group then
        group = {name = item.name, ids = {}, allowed = false, selected = false, protected = 0}
        byName[item.name] = group; groups[#groups + 1] = group
      end
      group.ids[#group.ids + 1] = key; count = count + 1
      if key == selected then group.selected = true end
      if owner.room.eligible(item) then
        group.allowed = group.allowed or owner.room.matchesAllowlist(item, allowed)
      else group.protected = group.protected + 1 end
    end
  end
  table.sort(groups, nameLess)
  for _, group in ipairs(groups) do
    table.sort(group.ids, idLess)
    local actions, hints = {}, {}
    for _, key in ipairs(group.ids) do
      if owner.room.eligible(owner.room.items[key]) then
        actions[#actions + 1] = targetAction(key); hints[#hints + 1] = 'Target ID ' .. key
      end
    end
    local groupName, area = group.name, owner.room.area
    if area and group.protected < #group.ids then
      actions[#actions + 1] = callback(function()
        if owner.room.area ~= area or not owner.room.ready then return false end
        for _, item in pairs(owner.room.items) do
          if item.name == groupName and not owner.room.retired[item.id] and owner.room.eligible(item) then return true end
        end
        return false
      end, function() owner.hunt.add(groupName) end)
      hints[#hints + 1] = 'Add name to this area\'s hunt list'
    end
    local text = (group.selected and '[T] ' or '') .. group.name
    if #group.ids > 1 then text = text .. ' x' .. #group.ids end
    if group.selected then
      text = text .. ' [ID ' .. selected .. ': ' .. owner.health.label(selected) .. ']'
    end
    if group.protected > 0 then
      text = text .. (group.protected == #group.ids and ' [protected]' or ' [' .. group.protected .. ' protected]')
    end
    local color = group.protected == #group.ids and 'muted'
      or (group.selected and 'selected' or (group.allowed and 'allowed' or 'normal'))
    write(console, text, color, actions, hints)
  end
  return count
end

local function items(console)
  local rows = {}
  for _, key in ipairs(owner.room.order) do
    local item = owner.room.items[key]
    if type(item) == 'table' and type(item.name) == 'string' and owner.trim(item.name) ~= ''
        and not owner.room.living(item) then rows[#rows + 1] = item end
  end
  table.sort(rows, function(a, b)
    if a.name == b.name then return idLess(a.id, b.id) end
    return nameLess(a, b)
  end)
  for _, item in ipairs(rows) do
    local key = item.id
    local function present() local live = itemNow(key); return live and not owner.room.living(live) end
    local actions = {
      callback(present, function() if type(send) == 'function' then send('get ' .. key) end end),
      callback(present, function() if type(send) == 'function' then send('probe ' .. key) end end)
    }
    local dead = type(item.attrib) == 'string' and item.attrib:lower():find('d', 1, true)
    write(console, item.name .. ' (' .. key .. ')', dead and 'muted' or 'items', actions, {'Get ID ' .. key, 'Probe ID ' .. key})
  end
  return #rows
end

local function selfName()
  local char = type(gmcp) == 'table' and gmcp.Char
  if type(char) ~= 'table' then return '' end
  local name = type(char.Name) == 'table' and char.Name.name
    or (type(char.Status) == 'table' and char.Status.name)
  return owner.norm(name)
end

local function players(console)
  local rows, ownName = {}, selfName()
  for key, player in pairs(owner.room.players) do if key ~= ownName then rows[#rows + 1] = player end end
  table.sort(rows, nameLess)
  for _, player in ipairs(rows) do
    local name, key = player.name, player.name:lower()
    local action = callback(function()
      return owner.room.playersReady and owner.room.players[key] ~= nil and key ~= selfName()
    end, function() owner.targeting.setPlayer(name) end)
    local selected = owner.targeting.kind == 'player' and owner.norm(owner.target) == key
    write(console, (selected and '[T] ' or '') .. name, selected and 'selected' or 'players', {action}, {'Target ' .. name .. ': ' .. literal(player.fullname)})
  end
  return #rows
end

local renderers = {denizens = denizens, items = items, players = players}
local function renderPanel(kind)
  local panel, room = ui.panels[kind], owner.room
  local console, count = panel.console, 0
  console:clear()
  if kind == 'players' and room.num then
    write(console, room.name or 'Unknown room', 'normal')
    write(console, (room.area or 'Unknown area') .. ' (' .. room.num .. ')', 'muted')
    console:echo('\n')
  end
  if not room.num then
    write(console, room.disconnected and 'Disconnected' or 'Waiting for room information...', 'muted')
  elseif not (kind == 'players' and room.playersReady or kind ~= 'players' and room.ready) then
    write(console, kind == 'players' and 'Waiting for players...' or 'Waiting for room contents...', 'muted')
  else
    count = renderers[kind](console)
    if count == 0 then write(console, 'None', 'muted') end
  end
  panel.container:setTitle(titles[kind] .. ' (' .. count .. ')', ui.palette.accent)
end

function ui.render()
  if not current() or not ui.initialized then return end
  for _, kind in ipairs(kinds) do safe(renderPanel, kind) end
end

function ui.requestRender()
  if not current() or not ui.initialized or owner.runtime.timers['ui-render'] then return end
  owner.defer('ui-render', 0, ui.render)
end

local function dispose(save)
  for _, kind in ipairs(kinds) do
    local panel = ui.panels[kind]
    if panel then
      local container = panel.container
      if save then safe(function() container:save() end) end
      safe(function() container:disableAutoSave() end)
      safe(function() if container.delete then container:delete() else container:hide() end end)
      ui.panels[kind] = nil
    end
  end
  ui.initialized = false
end

function ui.init()
  if not current() then return false end
  if ui.initialized then return true end
  if not (Geyser and Geyser.Label and Geyser.MiniConsole and Adjustable and Adjustable.Container) then return false end
  local ok = safe(function()
    for _, kind in ipairs(kinds) do
      local name = 'Demonic.RoomUI.' .. titles[kind]
      local container = assert(Adjustable.Container:new({
        name = name, x = 0, y = positions[kind], width = 300, height = '31%',
        titleText = titles[kind], titleTxtColor = ui.palette.accent, padding = 8,
        adjLabelstyle = 'background-color: ' .. ui.palette.background .. '; border: 2px solid ' .. ui.palette.border .. '; border-radius: 7px;',
        buttonstyle = 'QLabel { background-color: #462438; color: #ddc5eb; border-radius: 4px; }',
        autoSave = false, autoLoad = true
      }), 'Could not create the ' .. titles[kind] .. ' container.')
      ui.panels[kind] = {container = container}
      local back = assert(Geyser.Label:new({name = name .. '.Background', x = 0, y = 0, width = '100%', height = '100%'}, container),
        'Could not create the ' .. titles[kind] .. ' background.')
      back:setStyleSheet('background-color: ' .. ui.palette.background .. ';')
      ui.panels[kind].console = assert(Geyser.MiniConsole:new({
        name = name .. '.List', x = 5, y = 4, width = '-10px', height = '-8px',
        color = ui.palette.background, fontSize = 10, autoWrap = true, scrollBar = true
      }, back), 'Could not create the ' .. titles[kind] .. ' console.')
    end
  end)
  if not ok then dispose(false); return false end
  ui.initialized = true
  ui.render()
  safe(requestMissing)
  return true
end

function ui.show()
  if not ui.init() then return false end
  for _, kind in ipairs(kinds) do safe(function() ui.panels[kind].container:show() end) end
  ui.render(); safe(requestMissing)
  return true
end

function ui.hide()
  if not current() or not ui.initialized then return false end
  for _, kind in ipairs(kinds) do safe(function() ui.panels[kind].container:hide() end) end
  return true
end

function ui.resetLayout()
  if not ui.init() then return false end
  for _, kind in ipairs(kinds) do
    safe(function()
      local container = ui.panels[kind].container
      container:disconnect(); container:detach(); container:unlockContainer(); container:restore()
      container:move(0, positions[kind]); container:resize(300, '31%'); container:show(); container:save()
    end)
  end
  ui.render(); safe(requestMissing)
  return true
end

function ui.shutdown()
  if stopped then return end
  stopped = true; owner.cancel('ui-render'); dispose(true)
end

owner.bind('dem.roomChanged', function(_, reason)
  if not current() or not ui.initialized then return end
  if reason == 'identity' or reason == 'reset' then
    owner.cancel('ui-render'); ui.render()
    if reason == 'identity' then safe(requestMissing) end
  else ui.requestRender() end
end)
owner.bind('dem.targetChanged', ui.requestRender)
owner.bind('dem.healthChanged', ui.requestRender)
owner.bind('dem.huntListChanged', ui.requestRender)
