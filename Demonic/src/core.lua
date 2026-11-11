-- A reload owns a fresh runtime, but retains only validated profile settings.
if dem and type(dem.shutdown) == 'function' then dem.shutdown() end
dem = {
  profession = 'summoner',
  separator = '&&',
  runtime = {timers = {}, handlers = {}, gmcpFields = {}},
  settings = {areas = {}, hpLimit = 30, manaLimit = 10}
}
local owner = dem
local active = true

function dem.trim(value)
  return type(value) == 'string' and (value:gsub('^%s+', ''):gsub('%s+$', '')) or ''
end

function dem.norm(value)
  return dem.trim(value):gsub('%s+', ' '):lower()
end

function dem.validReference(value)
  if type(value) ~= 'string' then return nil, 'Target must be one word.' end
  -- Only ordinary surrounding spaces are harmless; tabs/newlines are rejected.
  local ref = value:gsub('^ +', ''):gsub(' +$', '')
  if ref == '' or not ref:match('^[A-Za-z0-9_%-]+$') then
    return nil, 'Target must contain only letters, digits, underscores or hyphens.'
  end
  return ref
end

function dem.message(value)
  local text = '[Demonic] ' .. tostring(value) .. '\n'
  if type(echo) == 'function' then echo(text)
  elseif type(cecho) == 'function' then cecho(text) end
end

function dem.now()
  if type(getEpoch) == 'function' then return getEpoch() end
  return os.time()
end

function dem.cancel(key)
  local timer = dem.runtime.timers[key]
  dem.runtime.timers[key] = nil
  if timer and type(killTimer) == 'function' then killTimer(timer.id) end
end

function dem.defer(key, seconds, callback)
  dem.cancel(key)
  if not active or type(tempTimer) ~= 'function' then return nil end
  local timer = {}
  dem.runtime.timers[key] = timer
  timer.id = tempTimer(seconds, function()
    if not active or dem ~= owner or owner.runtime.timers[key] ~= timer then return end
    owner.runtime.timers[key] = nil
    callback()
  end)
  return timer.id
end

function dem.bind(event, callback)
  if type(registerAnonymousEventHandler) ~= 'function' then return nil end
  local id = registerAnonymousEventHandler(event, function(...)
    if active and dem == owner then return callback(...) end
  end)
  dem.runtime.handlers[#dem.runtime.handlers + 1] = id
  return id
end

function dem.schedule()
  if not active or dem.runtime.timers['hunt-step'] then return end
  dem.defer('hunt-step', 0, function()
    dem.step()
  end)
end

function dem.step()
  dem.targeting.resolvePending()
  dem.defences.step()
  dem.hunt.step()
end

function dem.joinCommands(commands)
  if type(commands) ~= 'table' or #commands == 0 then return nil, 'No commands supplied.' end
  for i = 1, #commands do
    if type(commands[i]) ~= 'string' or dem.trim(commands[i]) == '' or commands[i]:find('[%c]') then
      return nil, 'Commands must be nonempty single-line strings.'
    end
  end
  return table.concat(commands, dem.separator)
end

local home = type(getMudletHomeDir) == 'function' and getMudletHomeDir() or '.'
dem.settingsPath = home .. '/Demonic-settings.lua'
local loaded = {}
if type(table.load) == 'function' then pcall(table.load, dem.settingsPath, loaded) end
for _, field in ipairs({'hpLimit', 'manaLimit'}) do
  local value = tonumber(loaded[field])
  if value and value == value and value >= 0 and value <= 100 then dem.settings[field] = value end
end
if type(loaded.areas) == 'table' then
  for area, names in pairs(loaded.areas) do
    -- Room.Info area labels are opaque keys; preserve their spelling on reload.
    local key = type(area) == 'string' and area or ''
    if dem.trim(key) ~= '' and type(names) == 'table' then
      dem.settings.areas[key] = dem.settings.areas[key] or {}
      for name, allowed in pairs(names) do
        local normalized = dem.norm(name)
        if normalized ~= '' and allowed == true then dem.settings.areas[key][normalized] = true end
      end
    end
  end
end

function dem.saveSettings()
  if type(table.save) ~= 'function' then dem.message('Settings could not be saved: table.save unavailable.'); return false end
  local ok, err = pcall(table.save, dem.settingsPath, dem.settings)
  if not ok then dem.message('Settings could not be saved: ' .. tostring(err)) end
  return ok
end

function dem.shutdown()
  if not active then return end
  active = false
  if dem.defences then dem.defences.reset('Package stopped.') end
  if dem.ui and type(dem.ui.shutdown) == 'function' then pcall(dem.ui.shutdown) end
  if dem.hunt then
    if type(dem.hunt.stop) == 'function' then dem.hunt.stop('Package stopped.')
    else dem.hunt.enabled = false end
  end
  local keys = {}
  for key in pairs(dem.runtime.timers) do keys[#keys + 1] = key end
  for _, key in ipairs(keys) do dem.cancel(key) end
  for _, id in ipairs(dem.runtime.handlers) do
    if type(killAnonymousEventHandler) == 'function' then killAnonymousEventHandler(id) end
  end
  dem.runtime.handlers = {}
end
