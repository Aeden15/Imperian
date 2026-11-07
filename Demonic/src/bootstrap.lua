-- Register only after every System and profession module has been loaded.
function dem.onPrompt(text)
  dem.cancel('hunt-step')
  if text then dem.balances.parsePrompt(text) end
  dem.room.onPrompt()
  dem.targeting.resolvePending()
  dem.hunt.step()
  dem.balances.endPrompt()
end

function dem.resetConnection()
  dem.hunt.stop('Connection changed; type hunt to enable again.')
  dem.hunt.lastAction = nil
  dem.targeting.clear('system')
  dem.balances.reset()
  dem.room.reset()
end

local function gmcpHandler(event, fn)
  dem.bind('gmcp.' .. event, function()
    local value = gmcp
    for field in event:gmatch('[^.]+') do
      value = type(value) == 'table' and value[field] or nil
    end
    if value ~= nil then fn(value) end
  end)
end

gmcpHandler('Char.Vitals', dem.balances.onVitals)
gmcpHandler('Room.Info', dem.room.onInfo)
gmcpHandler('Room.WrongDir', dem.room.onWrongDir)
gmcpHandler('Char.Items.List', dem.room.onList)
gmcpHandler('Char.Items.Add', dem.room.onAdd)
gmcpHandler('Char.Items.Remove', dem.room.onRemove)
gmcpHandler('Char.Items.Update', dem.room.onUpdate)
dem.bind('sysDataSendRequest', function(_, command) dem.room.onMovement(command) end)
dem.bind('sysDisconnectionEvent', dem.resetConnection)
dem.bind('sysConnectionEvent', dem.resetConnection)
dem.bind('sysProtocolEnabled', function(_, protocol)
  if protocol == 'GMCP' then dem.room.subscribe() end
end)
dem.bind('sysExitEvent', function() dem.saveSettings(); dem.shutdown() end)
dem.bind('sysUninstall', function(_, package)
  if package == 'Demonic' then dem.saveSettings(); dem.shutdown() end
end)

-- Installation into an already-connected profile may precede the next packet.
-- Hydrate vitals and room identity, but never trust a cached room item list.
if type(gmcp) == 'table' then
  if gmcp.Char or gmcp.Room then dem.room.subscribe() end
  if gmcp.Char and type(gmcp.Char.Vitals) == 'table' then
    dem.balances.onVitals(gmcp.Char.Vitals)
  end
  if gmcp.Room and type(gmcp.Room.Info) == 'table' then
    dem.room.onInfo(gmcp.Room.Info)
    -- This identity was cached before installation, rather than received during
    -- a movement block. Request a fresh roster without waiting for game text.
    dem.room.request('Installation into a connected profile')
  end
end
