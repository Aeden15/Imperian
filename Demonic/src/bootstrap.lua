-- Register only after every System and profession module has been loaded.
function dem.onPrompt(text)
  dem.cancel('hunt-step')
  dem.runtime.promptSerial = (dem.runtime.promptSerial or 0) + 1
  if text then dem.balances.parsePrompt(text) end
  dem.balances.onPrompt()
  dem.step()
  dem.balances.endPrompt()
end

function dem.resetConnection(event)
  dem.defences.reset('Connection changed; type ddef to run the defence sequence again.')
  dem.hunt.stop('Connection changed; type hunt to enable again.')
  dem.hunt.lastAction = nil
  dem.hunt.resetTerminalHistory()
  dem.targeting.clear('system')
  dem.balances.reset()
  dem.room.reset(event == 'sysDisconnectionEvent')
end

function dem.onDeath()
  dem.defences.reset('You are dead.')
  dem.hunt.stop('You are dead.')
  dem.hunt.lastAction = nil
  dem.hunt.resetTerminalHistory()
  dem.targeting.clear('system')
  dem.balances.clearForDeath()
  dem.room.reset()
end

function dem.onBalanceUnavailable(kind)
  return dem.balances.taken(kind)
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
gmcpHandler('Room.Players', dem.room.onPlayers)
gmcpHandler('Room.AddPlayer', dem.room.onAddPlayer)
gmcpHandler('Room.RemovePlayer', dem.room.onRemovePlayer)
gmcpHandler('Char.Name', function() dem.room.notify('players') end)
gmcpHandler('Char.Status', function() dem.room.notify('players') end)
gmcpHandler('Char.Items.List', dem.room.onList)
gmcpHandler('Char.Items.Add', dem.room.onAdd)
gmcpHandler('Char.Items.Remove', dem.room.onRemove)
gmcpHandler('Char.Items.Update', dem.room.onUpdate)
dem.bind('sysDisconnectionEvent', dem.resetConnection)
dem.bind('sysConnectionEvent', dem.resetConnection)
dem.bind('sysProtocolEnabled', function(_, protocol)
  if protocol == 'GMCP' then dem.room.subscribe() end
end)
dem.bind('sysLoadEvent', function() dem.ui.init() end)
dem.bind('sysExitEvent', function() dem.saveSettings(); dem.shutdown() end)
dem.bind('sysUninstall', function(_, package)
  if package == 'Demonic' then dem.saveSettings(); dem.shutdown() end
end)

dem.ui.init()

-- Installation into an already-connected profile may precede the next packet.
-- Hydrate vitals and room identity, but never trust a cached room item list.
if type(gmcp) == 'table' then
  if gmcp.Char or gmcp.Room then dem.room.subscribe() end
  if gmcp.Char and type(gmcp.Char.Vitals) == 'table' then
    dem.balances.onVitals(gmcp.Char.Vitals)
  end
  if gmcp.Room and type(gmcp.Room.Info) == 'table' then
    dem.room.onInfo(gmcp.Room.Info)
    -- The identity is cached; its item list must be requested afresh.
    dem.room.request('Installation into a connected profile')
  end
end
