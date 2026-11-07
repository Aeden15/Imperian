local tests, failed, passed = {}, 0, 0
local sent, gmcpSent, timers, handlers, saved, now, messages
local function test(name, body) tests[#tests + 1] = {name, body} end
local function eq(got, want)
  assert(got == want, 'expected ' .. tostring(want) .. ', got ' .. tostring(got))
end
local function reset(keepSettings)
  dem = nil
  sent, gmcpSent, timers, handlers, now, messages = {}, {}, {}, {}, 0, {}
  if not keepSettings then saved = nil end
  gmcp = {}
  function send(s) sent[#sent + 1] = s end
  function sendGMCP(s) gmcpSent[#gmcpSent + 1] = s end
  function cecho(s) messages[#messages + 1] = s end
  function getEpoch() return now end
  function getMudletHomeDir() return '/test-profile' end
  function tempTimer(seconds, fn)
    local id = #timers + 1
    timers[id] = {at = now + seconds, fn = fn, active = true}
    return id
  end
  function killTimer(id) if timers[id] then timers[id].active = false end end
  function registerAnonymousEventHandler(event, fn)
    local id = #handlers + 1
    handlers[id] = {event = event, fn = fn, active = true}
    return id
  end
  function killAnonymousEventHandler(id) if handlers[id] then handlers[id].active = false end end
  function raiseEvent(event, ...)
    local copy = {}
    for _, h in ipairs(handlers) do copy[#copy + 1] = h end
    for _, h in ipairs(copy) do if h.active and h.event == event then h.fn(event, ...) end end
  end
  table.save = function(_, value)
    saved = {areas = {}, hpLimit = value.hpLimit, manaLimit = value.manaLimit}
    for area, names in pairs(value.areas) do
      saved.areas[area] = {}
      for name, yes in pairs(names) do saved.areas[area][name] = yes end
    end
  end
  table.load = function(_, value)
    if not saved then error('no settings') end
    for k, v in pairs(saved) do value[k] = v end
  end
  DEMONIC_TEST_LOAD()
  assert(dem and dem.targeting, 'shared targeting is not implemented in the package')
end
local function event(name, payload)
  local node = gmcp
  local parts = {}
  for p in name:gmatch('[^.]+') do parts[#parts + 1] = p end
  for i = 1, #parts - 1 do node[parts[i]] = node[parts[i]] or {}; node = node[parts[i]] end
  node[parts[#parts]] = payload
  raiseEvent('gmcp.' .. name)
end
local function tick(seconds)
  now = now + seconds
  for _, timer in ipairs(timers) do
    if timer.active and timer.at <= now then timer.active = false; timer.fn() end
  end
end
local function vitals(overrides)
  local v = {bal='1', eq='1', hp='3998', maxhp='3998', mp='4459', maxmp='4772', prone='0', stunned='0', health='1'}
  for k, value in pairs(overrides or {}) do v[k] = value end
  event('Char.Vitals', v)
end
local function room(area, id)
  event('Room.Info', {num=id or 101, name='A room', area=area or 'Ant colony'})
end
local function roster(items) event('Char.Items.List', {location='room', items=items or {
  {id='1234',name='a warrior ant',attrib='m'}, {id='2335',name='Fido',attrib='m'}
}}) end
local function setup()
  vitals(); room(); dem.onPrompt(); roster()
  dem.hunt.add('a warrior ant')
end
local function start()
  setup(); dem.hunt.toggle(); roster(); dem.onPrompt()
end
local function cycle()
  vitals({bal='0'}); dem.onPrompt(); vitals(); dem.onPrompt()
end

test('target references remain one unchanged string', function()
  for _, ref in ipairs({'fido','fido1234','1234'}) do
    reset(); assert(dem.targeting.setDenizen(ref)); eq(dem.target, ref)
    eq(dem.ritualism.buildTrace({'fire','ice'}, dem.target), 'trace fire ice ' .. ref)
  end
end)
test('target validation prevents command injection without changing selection', function()
  reset(); dem.targeting.setDenizen('fido')
  for _, ref in ipairs({'fido;quit','fido|quit','fido\nquit','fido quit','', 'fido\tquit'}) do
    assert(not dem.targeting.setDenizen(ref)); eq(dem.target,'fido')
  end
end)
test('all command joining uses the shared double ampersand separator', function()
  reset(); eq(dem.separator,'&&')
  eq(dem.joinCommands({'stand','trace fire ice fido1234'}),'stand&&trace fire ice fido1234')
  assert(not dem.targeting.setDenizen('fido&&quit'))
end)
test('Duality is passive and rejects a third symbol', function()
  reset(); eq(dem.ritualism.buildTrace({'fire','ice'},'fido1234'),'trace fire ice fido1234')
  assert(not dem.ritualism.buildTrace({'fire','ice','fire'},'fido'))
  dem.ritualism.duality = false
  assert(not dem.ritualism.buildTrace({'fire','ice'},'fido'))
  eq(dem.ritualism.buildTrace({'fire'},'fido'),'trace fire fido')
  eq(#sent,0)
end)
test('hunt waits for a fresh roster and submits one combined attack', function()
  reset(); setup(); dem.hunt.toggle(); dem.onPrompt(); eq(#sent,0)
  roster(); dem.onPrompt(); eq(sent[1],'trace fire ice 1234'); eq(#sent,1)
end)
test('stale ready packets and duplicate prompts never repeat a pending attack', function()
  reset(); start(); vitals(); dem.onPrompt(); dem.onPrompt(); eq(#sent,1)
  cycle(); eq(#sent,2)
end)
test('reported cooldown expiration cannot grant readiness', function()
  reset(); start(); dem.balances.taken('bal',2.70); tick(3); dem.onPrompt(); eq(#sent,1)
  dem.balances.recovered('bal'); dem.onPrompt(); eq(#sent,2)
end)
test('equilibrium loss, stunned, and prone block attacks', function()
  for _, block in ipairs({'eq','stunned','prone'}) do
    reset(); setup(); vitals({[block] = block == 'eq' and '0' or '1'})
    dem.hunt.toggle(); roster(); dem.onPrompt(); eq(#sent,0)
    vitals(); dem.onPrompt(); eq(#sent,1)
  end
end)
test('low health or mana disables hunting and never auto resumes', function()
  for _, low in ipairs({{hp='1199'},{mp='477'}}) do
    reset(); setup(); vitals(low); dem.hunt.toggle(); roster(); dem.onPrompt()
    assert(not dem.hunt.enabled); eq(#sent,0)
    vitals(); dem.onPrompt(); eq(#sent,0)
  end
end)
test('the full Duality command needs eighteen mana', function()
  reset(); setup(); dem.hunt.setLimits(0,0); vitals({mp='17'})
  dem.hunt.toggle(); roster(); dem.onPrompt(); eq(#sent,0)
end)
test('missing or malformed maximum vitals do not authorize attacks', function()
  reset(); room(); dem.onPrompt(); roster(); dem.hunt.add('a warrior ant')
  event('Char.Vitals',{bal='1',eq='1',hp='3998',mp='4459',maxhp='bad',maxmp='0'})
  dem.hunt.toggle(); roster(); dem.onPrompt(); eq(#sent,0)
end)
test('partial GMCP retains known fields but malformed explicit fields invalidate them', function()
  reset(); setup(); event('Char.Vitals',{bal='0'})
  dem.hunt.toggle(); roster(); dem.onPrompt(); eq(#sent,0)
  event('Char.Vitals',{bal='1'}); dem.onPrompt(); eq(#sent,1)
  event('Char.Vitals',{hp='bad'}); event('Char.Vitals',{bal='0'}); event('Char.Vitals',{bal='1'})
  dem.onPrompt(); eq(#sent,1)
end)
test('sample text fallback updates balance and vitals without estimating maxima', function()
  reset(); setup(); dem.hunt.setLimits(0,0); dem.hunt.toggle(); roster()
  dem.onPrompt('Health:312 Mana:331 (e-)'); eq(#sent,0)
  dem.onPrompt('Health:3998 Mana:4459 (eb)'); eq(#sent,1)
end)
test('same prompt valid GMCP wins over conflicting text fields', function()
  reset(); setup(); dem.hunt.toggle(); roster(); vitals()
  dem.onPrompt('Health:1 Mana:1 (-- )'); eq(sent[1],'trace fire ice 1234')
end)
test('an empty area allowlist stays enabled and idle', function()
  reset(); vitals(); room(); dem.onPrompt(); roster(); dem.hunt.toggle(); roster(); dem.onPrompt()
  assert(dem.hunt.enabled); eq(#sent,0)
end)
test('dead protected ordinary items and inventory entries are never auto attacked', function()
  reset(); setup(); dem.hunt.toggle()
  roster({{id='1',name='a warrior ant',attrib='md'},{id='2',name='a warrior ant',attrib='mx'},
    {id='3',name='a warrior ant',attrib='t'}})
  event('Char.Items.List',{location='inv',items={{id='4',name='a warrior ant',attrib='m'}}})
  dem.onPrompt(); eq(#sent,0)
end)
test('area lists persist independently and never inherit an unknown area', function()
  reset(); setup(); room('Other area',102); dem.onPrompt(); roster()
  dem.hunt.toggle(); roster(); dem.onPrompt(); eq(#sent,0)
  dem.hunt.add('Fido'); dem.onPrompt(); eq(sent[1],'trace fire ice 2335')
  reset(true); vitals(); room('Ant colony'); dem.onPrompt(); roster()
  dem.hunt.toggle(); roster(); dem.onPrompt(); eq(sent[1],'trace fire ice 1234')
  room(nil,103); event('Room.Info',{num=104,name='Unknown area'}); dem.onPrompt(); roster()
  cycle(); eq(#sent,1)
end)
test('manual player selection disables hunting and preserves its target', function()
  reset(); start(); dem.targeting.setPlayer('Aeden'); eq(dem.target,'Aeden')
  assert(not dem.hunt.enabled); cycle(); eq(#sent,1)
end)
test('manual denizen selection switches only after prior balance recovers', function()
  reset(); start(); dem.targeting.setDenizen('fido2335'); eq(dem.target,'fido2335')
  dem.onPrompt(); eq(#sent,1); cycle(); eq(sent[2],'trace fire ice fido2335')
end)
test('manual bare name and ID references can switch hunting', function()
  for _, ref in ipairs({'fido','2335'}) do
    reset(); start(); dem.targeting.setDenizen(ref); cycle()
    eq(sent[2],'trace fire ice '..ref)
  end
end)
test('old attack kill and trailing error preserve a newly selected target', function()
  reset(); start(); dem.targeting.setDenizen('fido2335')
  dem.hunt.onKill('a warrior ant'); dem.hunt.onMissing(); roster(); cycle()
  eq(dem.target,'fido2335'); eq(sent[2],'trace fire ice fido2335')
end)
test('manual override does not add a name to the area allowlist', function()
  reset(); start(); dem.targeting.setDenizen('fido'); cycle()
  dem.hunt.onKill('Fido'); roster(); cycle()
  eq(sent[3],'trace fire ice 1234')
end)
test('manual protected denizens stop the basher but remain globally targetable', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='9',name='a guard',attrib='mx'}})
  assert(dem.targeting.setDenizen('9')); eq(dem.target,'9'); assert(not dem.hunt.enabled)
end)
test('clear and toggle off cancel future sends without re granting balance', function()
  reset(); start(); dem.targeting.clear(); assert(not dem.hunt.enabled); eq(dem.target,nil)
  dem.onPrompt(); tick(20); eq(#sent,1)
  dem.hunt.toggle(); roster(); dem.onPrompt(); eq(#sent,1)
  cycle(); eq(#sent,2)
end)
test('moving while pending waits for new room roster and old cooldown', function()
  reset(); start(); room('Ant colony',102); roster(); dem.onPrompt()
  dem.onPrompt(); eq(#sent,1); roster(); dem.onPrompt(); eq(#sent,1)
  cycle(); eq(#sent,2); assert(dem.hunt.enabled)
end)
test('room arrivals and scalar or object removals update candidates', function()
  reset(); setup(); dem.hunt.toggle(); roster({}); dem.onPrompt(); eq(#sent,0)
  event('Char.Items.Add',{location='room',item={id='7',name='a warrior ant',attrib='m'}})
  dem.onPrompt(); eq(sent[1],'trace fire ice 7')
  event('Char.Items.Remove',{location='room',item='7'}); cycle(); eq(#sent,1)
  event('Char.Items.Add',{location='room',item={id='8',name='a warrior ant',attrib='m'}})
  dem.onPrompt(); eq(sent[2],'trace fire ice 8')
  event('Char.Items.Remove',{location='room',item={id='8'}}); cycle(); eq(#sent,2)
end)
test('watchdog disables unresolved attacks without retrying', function()
  reset(); start(); tick(11); dem.onPrompt(); assert(not dem.hunt.enabled); eq(#sent,1)
end)
test('disconnect clears connection data and prohibits automatic restart', function()
  reset(); start(); raiseEvent('sysDisconnectionEvent'); eq(dem.target,nil)
  assert(not dem.hunt.enabled); vitals(); room(); roster(); dem.onPrompt(); eq(#sent,1)
end)
test('reload removes old handlers and pending timers', function()
  reset(); start(); DEMONIC_TEST_LOAD(); assert(not dem.hunt.enabled)
  local active = {}
  for _, h in ipairs(handlers) do if h.active then active[h.event]=(active[h.event] or 0)+1 end end
  for _, count in pairs(active) do eq(count,1) end
  tick(20); eq(#sent,1)
end)
test('installation in an already connected idle profile requests fresh contents', function()
  reset(); vitals(); room(); roster()
  gmcpSent = {}; DEMONIC_TEST_LOAD()
  assert(not dem.hunt.enabled); assert(not dem.room.ready)
  local requested, subscribed = false, false
  for _, msg in ipairs(gmcpSent) do
    if msg == 'Char.Items.Room' then requested = true end
    if msg:find('Core.Supports.Add',1,true) then subscribed = true end
  end
  assert(requested and subscribed, 'install must subscribe and refresh without another game prompt')
end)
test('GMCP only roster and recovery events drive hunting without extra text', function()
  reset(); setup(); dem.hunt.toggle(); roster(); tick(0); eq(#sent,1)
  vitals({bal='0'}); tick(0); vitals(); tick(0); eq(#sent,2)
end)
test('removing an unsubmitted manual target ends its temporary exception', function()
  reset(); start(); dem.targeting.setDenizen('fido2335')
  event('Char.Items.Remove',{location='room',item='2335'}); cycle()
  assert(dem.hunt.enabled); eq(sent[2],'trace fire ice 1234')
end)
test('a protected update stops manual hunting without clearing shared selection', function()
  reset(); start(); dem.targeting.setDenizen('fido')
  event('Char.Items.Update',{location='room',item={id='2335',attrib='mx'}})
  tick(0)
  assert(not dem.hunt.enabled); eq(dem.target,'fido'); cycle(); eq(#sent,1)
end)
test('movement clears a manually selected denizen from the prior room', function()
  reset(); setup(); dem.targeting.setDenizen('fido'); room('Empty area',102)
  eq(dem.target,nil); dem.onPrompt(); roster({})
  dem.hunt.toggle(); roster({}); dem.onPrompt(); eq(#sent,0)
end)
test('duplicate denizen names require a specific manual reference', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='2336',name='Fido',attrib='m'}})
  dem.targeting.setDenizen('fido'); assert(not dem.hunt.enabled)
  dem.targeting.setDenizen('fido2335'); dem.hunt.toggle(); roster({
    {id='1234',name='a warrior ant',attrib='m'}, {id='2335',name='Fido',attrib='m'}, {id='2336',name='Fido',attrib='m'}})
  cycle(); eq(sent[2],'trace fire ice fido2335')
end)
test('room synchronization timeout turns mode off rather than using a cached list', function()
  reset(); setup(); dem.hunt.toggle(); tick(11)
  assert(not dem.hunt.enabled); eq(#sent,0)
end)
test('explicit respawn arrival can revive an ID suppressed by an earlier kill', function()
  reset(); start(); dem.hunt.onKill('a warrior ant'); roster({}); cycle(); eq(#sent,1)
  event('Char.Items.Add',{location='room',item={id='1234',name='a warrior ant',attrib='m'}})
  dem.onPrompt(); eq(sent[2],'trace fire ice 1234')
end)
test('stale snapshots cannot revive a denizen already killed in this room', function()
  reset(); start(); dem.hunt.onKill('a warrior ant'); dem.hunt.onMissing(); roster(); cycle()
  eq(#sent,1); assert(dem.hunt.enabled)
end)
test('profile limits persist but player targets and enabled state do not', function()
  reset(); setup(); dem.hunt.setLimits(45,20); dem.targeting.setPlayer('Aeden')
  reset(true); eq(dem.settings.hpLimit,45); eq(dem.settings.manaLimit,20)
  eq(dem.target,nil); assert(not dem.hunt.enabled)
end)
test('uninstall cancels timers and disconnects event consumers', function()
  reset(); start(); raiseEvent('sysUninstall','Demonic'); tick(20)
  assert(not dem.hunt.enabled); eq(#sent,1)
  for _, h in ipairs(handlers) do assert(not h.active) end
end)
test('another package uninstall does not disable Demonic', function()
  reset(); start(); raiseEvent('sysUninstall','OtherPackage')
  assert(dem.hunt.enabled); cycle(); eq(#sent,2)
end)
test('a shared target event consumer can select a player before any hunting send', function()
  reset(); setup()
  dem.bind('dem.targetChanged',function(_, _, _, kind, source)
    if kind == 'denizen' and source == 'hunt' then dem.targeting.setPlayer('Aeden') end
  end)
  dem.hunt.toggle(); roster(); dem.onPrompt()
  eq(#sent,0); eq(dem.target,'Aeden'); assert(not dem.hunt.enabled)
end)
test('a manual override removed during roster refresh returns to the area list', function()
  reset(); start(); dem.hunt.onKill('a warrior ant')
  dem.targeting.setDenizen('fido2335')
  event('Char.Items.Remove',{location='room',item='2335'})
  roster({{id='9',name='a warrior ant',attrib='m'}}); cycle()
  assert(dem.hunt.enabled); eq(sent[2],'trace fire ice 9')
end)
test('a refresh snapshot can end an override that disappeared without a delta', function()
  reset(); start(); dem.hunt.onKill('a warrior ant')
  dem.targeting.setDenizen('fido2335')
  roster({{id='9',name='a warrior ant',attrib='m'}}); cycle()
  assert(dem.hunt.enabled); eq(sent[2],'trace fire ice 9')
end)
test('a truly unknown reference selected during refresh never authorizes an attack', function()
  reset(); start(); dem.hunt.onKill('a warrior ant')
  dem.targeting.setDenizen('unknown9999'); roster(); cycle()
  assert(not dem.hunt.enabled); eq(#sent,1)
end)

for _, t in ipairs(tests) do
  local ok, err = pcall(t[2])
  if ok then passed=passed+1; print('PASS '..t[1])
  else failed=failed+1; print('FAIL '..t[1]..': '..tostring(err)) end
end
print(string.format('%d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
