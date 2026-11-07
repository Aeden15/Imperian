-- Class registry and maintenance share the same action gate as Hunt.
dem.diabolist = {defences = {
  {name = 'ouroboros', skill = 'malignosis', resource = 'prompt'},
  {name = 'armor', skill = 'malignosis', resource = 'prompt'},
  {name = 'regeneration', skill = 'malignosis', resource = 'prompt'},
  {name = 'soulmask', skill = 'malignosis', resource = 'prompt'},
  {name = 'syphon', skill = 'malignosis', resource = 'prompt'},
  {name = 'vitality', skill = 'ritualism', resource = 'bal', mana = 9},
  {name = 'nightfall', skill = 'nightfall', resource = 'eq', mana = 27}
}}
dem.defences = {enabled = false, active = {}, reason = 'Disabled.'}
local defences = dem.defences

function defences.stop(reason)
  local wasEnabled = defences.enabled
  defences.enabled = false
  defences.reason = reason or 'Disabled by user.'
  -- A pending command still owns its confirmation and recovery after toggling off.
  if wasEnabled then dem.message('Defence maintenance off: ' .. defences.reason) end
end

function defences.reset(reason)
  defences.stop(reason)
  defences.active = {}
  dem.cancel('defence-watchdog')
end

function defences.toggle()
  if defences.enabled then defences.stop(); return false end
  if dem.balances.dead then dem.message('Defence maintenance remains off while you are dead.'); return false end
  defences.enabled = true
  defences.reason = 'Waiting for character readiness.'
  dem.message('Defence maintenance on.')
  dem.schedule()
  return true
end

function defences.setActive(name, active)
  local known = false
  for _, entry in ipairs(dem.diabolist.defences) do
    if entry.name == name then known = true; break end
  end
  if not known or type(active) ~= 'boolean' then return false end
  defences.active[name] = active
  if name == 'ouroboros' and not active then
    for _, dependent in ipairs({'armor', 'regeneration', 'soulmask', 'syphon'}) do
      defences.active[dependent] = false
    end
  end
  local action = dem.balances.action
  if active and action and action.kind == 'defence' and action.defence == name then
    dem.balances.confirmDefence(action)
  end
  dem.schedule()
  return true
end

local function finite(n)
  return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

function defences.step()
  if not defences.enabled then return end
  local b, v = dem.balances, dem.vitals
  if b.dead then defences.stop('You are dead.'); return end
  if dem.hunt.enabled then defences.reason = 'Paused while Hunt is on.'; return end
  if b.action then defences.reason = 'Waiting for the current command confirmation and recovery.'; return end
  if not finite(v.hp) or v.hp <= 0 or not finite(v.mp) or v.mp < 0
      or not finite(v.maxmp) or v.maxmp <= 0 or v.prone == nil or v.stunned == nil then
    defences.reason = 'Waiting for character data.'; return
  end
  if v.mp / v.maxmp * 100 <= dem.settings.manaLimit then
    defences.stop('Mana reached the configured limit.'); return
  end
  if not b.bal or not b.eq or v.prone or v.stunned then
    defences.reason = 'Waiting for balance, equilibrium, standing and unstunned status.'; return
  end
  for _, entry in ipairs(dem.diabolist.defences) do
    if not defences.active[entry.name] then
      if entry.mana and v.mp < entry.mana then
        defences.reason = 'Waiting for enough mana for ' .. entry.name .. '.'; return
      end
      local skill = dem[entry.skill]
      local command = skill.buildDefence(entry.name)
      if not command then defences.stop('Cannot build ' .. entry.name .. '.'); return end
      local action = {kind = 'defence', defence = entry.name, resource = entry.resource, started = dem.now()}
      if not b.beginAction(action) then return end
      defences.reason = 'Waiting for ' .. entry.name .. ' confirmation and recovery.'
      dem.defer('defence-watchdog', 10, function()
        if b.action ~= action then return end
        defences.stop('No confirmed completion for ' .. entry.name .. '; check the game response before retrying.')
        if dem.hunt.enabled then dem.hunt.stop('The pending defence has not completed.') end
      end)
      send(command)
      return
    end
  end
  defences.reason = 'All listed defences are confirmed active.'
end
