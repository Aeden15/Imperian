-- The setup pass and optional maintenance share the action gate with Hunt.
local entries = {
  {name = 'arctar', command = 'summon arctar', resource = 'eq', mana = 27},
  {name = 'warmth', command = 'invoke warmth', resource = 'prompt'},
  {name = 'astralvision', command = 'invoke astralvision', resource = 'prompt'},
  {name = 'distortion', command = 'invoke distortion', resource = 'prompt'},
  {name = 'mindseye', command = 'touch mindseye', resource = 'prompt'}
}
local known = {shield = true}
for _, entry in ipairs(entries) do known[entry.name] = true end
dem.defences = {
  enabled = false, active = {}, reason = 'Disabled.',
  cooldowns = {arctar = false, unleash = false}, arctarMana = 18
}
local defences = dem.defences
local arctarLine, arctarUnleashed

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
  defences.cooldowns = {arctar = false, unleash = false}
  defences.endPrompt()
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
  if not known[name] or type(active) ~= 'boolean' then return false end
  defences.active[name] = active
  local action = dem.balances.action
  if active and action and action.kind == 'defence' and action.defence == name then
    dem.balances.confirmDefence(action)
  end
  dem.schedule()
  return true
end

function defences.onCooldownReady(name)
  if defences.cooldowns[name] == nil then return end
  defences.cooldowns[name] = false
  dem.schedule()
end

function defences.onShield(source)
  defences.setActive('shield', true)
  local action = dem.balances.action
  if action and action.kind == 'shield' and action.source == source
      and (source ~= 'arctar' or arctarUnleashed) then
    dem.balances.confirmAction(action)
  end
end

local arctarMessages = {
  summon = 'You close your eyes and reach out with your mind towards the Demon Plane, seeking out the presence of Arctar, the Defender. Your search is successful and a burden descends upon your soul as the possession takes hold.',
  banish = 'You close your eyes and focus all your willpower on the demon that is possessing you, driving away the presence of Arctar, the Defender.'
}
local unleashPrefix = 'You focus upon your pact and a terrifying visage of '
local arctarUnleashPrefix = unleashPrefix .. 'Arctar, the Defender appears briefly in front of '
local arctarSelf = arctarUnleashPrefix .. 'yourself, wreathed in flames.'

function defences.onArctarLine(line)
  if not arctarLine and line:sub(1, 23) ~= 'You close your eyes and'
      and line:sub(1, #unleashPrefix) ~= unleashPrefix then return end
  line = dem.trim(line):gsub('%s+', ' ')
  local candidate = arctarLine and (arctarLine .. ' ' .. line) or line
  arctarLine = nil
  for kind, message in pairs(arctarMessages) do
    if candidate == message then
      defences.setActive('arctar', kind == 'summon')
      return
    end
    if message:sub(1, #candidate + 1) == candidate .. ' ' then
      arctarLine = candidate
    end
  end
  if candidate:match('^You focus upon your pact and a terrifying visage of .+, wreathed in flames%.$') then
    defences.cooldowns.unleash = true
    if candidate:sub(1, #arctarUnleashPrefix) == arctarUnleashPrefix then
      defences.cooldowns.arctar = true
      arctarUnleashed = candidate == arctarSelf
    end
  elseif (#candidate < 300 and candidate:sub(1, #unleashPrefix) == unleashPrefix) then
    arctarLine = candidate
  end
end

function defences.endPrompt()
  arctarLine, arctarUnleashed = nil, nil
end

local function finite(n)
  return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function submit(entry, manualPass)
  local command = entry.command
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
  local entry = entries[pass.index]
  if not entry then defences.stop('Complete.'); return end
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
  for _, entry in ipairs(entries) do
    if not defences.active[entry.name] then
      if entry.mana and v.mp < entry.mana then
        defences.reason = 'Waiting for enough mana for ' .. entry.name .. '.'; return
      end
      submit(entry, false)
      return
    end
  end
  defences.reason = 'All listed defences are confirmed active.'
end
