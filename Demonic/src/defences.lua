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
  local wasPass = defences.pass ~= nil
  defences.enabled = false
  defences.pass = nil
  defences.reason = reason or 'Disabled by user.'
  -- A pending command still owns its confirmation and recovery after toggling off.
  if wasEnabled then
    dem.message((wasPass and 'Defence sequence: ' or 'Defence maintenance off: ') .. defences.reason)
  end
end

function defences.reset(reason)
  defences.stop(reason)
  defences.active = {}
  defences.vitalityCooldown = nil
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

-- The manual alias requests one complete pass; repeated use never cancels it.
function defences.run()
  if dem.balances.dead then dem.message('Cannot run defences while you are dead.'); return false end
  if not defences.enabled or not defences.pass then
    defences.pass = {index = 1}
    defences.enabled = true
  end
  defences.step()
  dem.message('Defence sequence: ' .. defences.reason)
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
  if name == 'vitality' and active then defences.vitalityCooldown = false end
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

function defences.onVitalityConsumed()
  defences.vitalityCooldown = true
  defences.setActive('vitality', false)
end

function defences.onVitalityReady()
  defences.vitalityCooldown = false
  dem.schedule()
end

function defences.onVitalityCooldown()
  defences.vitalityCooldown = true
  local action = dem.balances.action
  if action and action.kind == 'defence' and action.defence == 'vitality' then
    dem.balances.refuseDefence(action)
  end
  dem.schedule()
end

local function finite(n)
  return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function submit(entry, manualPass)
  local command = dem[entry.skill].buildDefence(entry.name)
  if not command then defences.stop('Cannot build ' .. entry.name .. '.'); return end
  local action = {kind = 'defence', defence = entry.name,
    resource = manualPass and 'prompt' or entry.resource, manualPass = manualPass, started = dem.now()}
  if not dem.balances.beginAction(action) then return end
  if manualPass then defences.pass.action = action end
  defences.reason = 'Submitted ' .. command .. '; waiting for ' .. (manualPass and 'a fresh ready prompt.' or 'confirmation and recovery.')
  dem.defer('defence-watchdog', 10, function()
    if dem.balances.action ~= action then return end
    defences.stop('No confirmed completion for ' .. entry.name .. '; check the game response before retrying.')
    if dem.hunt.enabled then dem.hunt.stop('The pending defence has not completed.') end
  end)
  send(command)
end

local function runPass()
  local pass, b, v = defences.pass, dem.balances, dem.vitals
  if pass.action and pass.action.completed then
    pass.index, pass.action = pass.index + 1, nil
  end
  local entry = dem.diabolist.defences[pass.index]
  if not entry then defences.stop('Complete; all seven commands submitted.'); return end
  if b.action then defences.reason = 'Waiting for the current command to finish.'; return end
  -- A manual pass can use the displayed compact prompt. It need not invent a
  -- maximum or assume the game reports optional prone/stunned GMCP fields.
  if not finite(v.hp) or v.hp <= 0 or not finite(v.mp) or v.mp < 0 then
    defences.reason = 'Waiting for a health/mana prompt.'; return
  end
  if finite(v.maxmp) and v.maxmp > 0 and v.mp / v.maxmp * 100 <= dem.settings.manaLimit then
    defences.stop('Mana reached the configured limit.'); return
  end
  if not b.bal or not b.eq or v.prone == true or v.stunned == true then
    defences.reason = 'Waiting for balance/equilibrium or a known incapacitation to clear.'; return
  end
  if entry.mana and v.mp < entry.mana then
    defences.reason = 'Waiting for enough mana for ' .. entry.name .. '.'; return
  end
  submit(entry, true)
end

function defences.step()
  if not defences.enabled then return end
  local b, v = dem.balances, dem.vitals
  if b.dead then defences.stop('You are dead.'); return end
  if dem.hunt.enabled then defences.reason = 'Paused while Hunt is on.'; return end
  if defences.pass then runPass(); return end
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
    if not defences.active[entry.name] and (entry.name ~= 'vitality' or not defences.vitalityCooldown) then
      if entry.mana and v.mp < entry.mana then
        defences.reason = 'Waiting for enough mana for ' .. entry.name .. '.'; return
      end
      submit(entry, false)
      return
    end
  end
  defences.reason = defences.vitalityCooldown and 'Vitality is unavailable; other listed defences are confirmed active.'
    or 'All listed defences are confirmed active.'
end
