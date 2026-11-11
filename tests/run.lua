local tests, failed, passed = {}, 0, 0
local sent, commands, gmcpSent, timers, handlers, saved, now, messages
local function test(name, body) tests[#tests + 1] = {name, body} end
local function eq(got, want)
  assert(got == want, 'expected ' .. tostring(want) .. ', got ' .. tostring(got))
end
local function reset(keepSettings)
  dem = nil
  sent, commands, gmcpSent, timers, handlers, now, messages = {}, {}, {}, {}, {}, 0, {}
  if not keepSettings then saved = nil end
  gmcp = {}
  function send(s)
    raiseEvent('sysDataSendRequest',s)
    commands[#commands + 1] = s
    if s:match('^invoke combustion ') or s == 'unleash arctar at me' or s == 'touch shield' then
      sent[#sent + 1] = s
    end
  end
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
  local target, iterations = now + seconds, 0
  while true do
    local nextTimer
    for _, timer in ipairs(timers) do
      if timer.active and timer.at <= target and (not nextTimer or timer.at < nextTimer.at) then nextTimer = timer end
    end
    if not nextTimer then break end
    iterations = iterations + 1; assert(iterations < 1000, 'timer loop did not settle')
    now = nextTimer.at; nextTimer.active = false; nextTimer.fn()
  end
  now = target
end
local function queryCount()
  local count = 0
  for _, message in ipairs(gmcpSent) do if message:match('^Char%.Items%.Room') then count=count+1 end end
  return count
end
local function commandCount(command)
  local count = 0
  for _, value in ipairs(commands) do if value == command then count=count+1 end end
  return count
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
  vitals({eq='0'}); dem.onPrompt(); vitals(); dem.onPrompt()
end

test('Summoner Hunt casts Combustion and ignores balance recovery', function()
  reset(); start()
  eq(commands[#commands], 'invoke combustion 1234')
  local action = dem.balances.action
  dem.balances.taken('bal'); dem.balances.recovered('bal'); dem.onPrompt()
  eq(dem.balances.action, action); eq(commandCount('invoke combustion 1234'), 1)
  dem.balances.taken('eq'); dem.balances.recovered('eq'); dem.onPrompt()
  eq(commandCount('invoke combustion 1234'), 2)
end)

test('generated Mindseye events set and clear shared defence state', function()
  reset()
  DEMONIC_TEST_DEFENCE_LOG('mindseye-up')
  eq(dem.defences.active.mindseye, true)
  DEMONIC_TEST_DEFENCE_LOG('mindseye-down')
  eq(dem.defences.active.mindseye, false)
  eq(#commands, 0)
end)

test('Arctar requires a confirmation and fresh prompt, then cooldowns clear independently', function()
  reset(); setup(); vitals({hp='40',maxhp='100'}); dem.hunt.toggle(); roster(); dem.onPrompt()
  eq(commands[#commands], 'unleash arctar at me')
  local action = dem.balances.action
  dem.onPrompt('Health:40 Mana:4459 (eb)'); eq(dem.balances.action, action)
  DEMONIC_TEST_DEFENCE_LOG('arctar-shield')
  eq(dem.defences.active.shield, true)
  dem.onPrompt(); eq(dem.balances.action, action)
  dem.onPrompt('Health:40 Mana:4459 (eb)'); eq(dem.balances.action, nil)
  DEMONIC_TEST_DEFENCE_LOG('unleash-ready')
  DEMONIC_TEST_DEFENCE_LOG('shield-down')
  dem.onPrompt(); eq(commands[#commands], 'touch shield')
  DEMONIC_TEST_DEFENCE_LOG('tattoo-shield')
  dem.balances.taken('eq'); dem.balances.recovered('eq'); dem.onPrompt()
  eq(commandCount('touch shield'), 1)
  DEMONIC_TEST_DEFENCE_LOG('arctar-ready')
  DEMONIC_TEST_DEFENCE_LOG('shield-down')
  dem.onPrompt(); eq(commandCount('unleash arctar at me'), 2)
end)

test('target references remain one unchanged string', function()
  for _, ref in ipairs({'fido','fido1234','1234'}) do
    reset(); assert(dem.targeting.setDenizen(ref)); eq(dem.target, ref)
    eq(dem.validReference(dem.target), ref)
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
  eq(dem.joinCommands({'stand','invoke combustion fido1234'}),'stand&&invoke combustion fido1234')
  assert(not dem.targeting.setDenizen('fido&&quit'))
end)
test('hunt waits for a fresh roster and submits one Combustion', function()
  reset(); setup(); dem.hunt.toggle(); dem.onPrompt(); eq(#sent,0)
  roster(); dem.onPrompt(); eq(sent[1],'invoke combustion 1234'); eq(#sent,1)
end)
test('stale ready packets and duplicate prompts never repeat a pending attack', function()
  reset(); start(); vitals(); dem.onPrompt(); dem.onPrompt(); eq(#sent,1)
  cycle(); eq(#sent,2)
end)
test('reported cooldown expiration cannot grant readiness', function()
  reset(); start(); dem.balances.taken('eq',2.70); tick(3); dem.onPrompt(); eq(#sent,1)
  dem.balances.recovered('eq'); dem.onPrompt(); eq(#sent,2)
end)
test('equilibrium loss, stunned, and prone block attacks', function()
  for _, block in ipairs({'eq','stunned','prone'}) do
    reset(); setup(); vitals({[block] = block == 'eq' and '0' or '1'})
    dem.hunt.toggle(); roster(); dem.onPrompt(); eq(#sent,0)
    vitals(); dem.onPrompt(); eq(#sent,1)
  end
end)
test('low mana disables hunting and never auto resumes', function()
  for _, low in ipairs({{mp='477'}}) do
    reset(); setup(); vitals(low); dem.hunt.toggle(); roster(); dem.onPrompt()
    assert(not dem.hunt.enabled); eq(#sent,0)
    vitals(); dem.onPrompt(); eq(#sent,0)
  end
end)
test('Combustion uses the configured mana floor without a guessed cost', function()
  reset(); setup(); dem.hunt.setLimits(0,0); vitals({mp='17'})
  dem.hunt.toggle(); roster(); dem.onPrompt(); eq(sent[1], 'invoke combustion 1234')
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
  dem.onPrompt('Health:1 Mana:1 (-- )'); eq(sent[1],'invoke combustion 1234')
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
  dem.hunt.add('Fido'); dem.onPrompt(); eq(sent[1],'invoke combustion 2335')
  reset(true); vitals(); room('Ant colony'); dem.onPrompt(); roster()
  dem.hunt.toggle(); roster(); dem.onPrompt(); eq(sent[1],'invoke combustion 1234')
  room(nil,103); event('Room.Info',{num=104,name='Unknown area'}); dem.onPrompt(); roster()
  cycle(); eq(#sent,1)
end)
test('manual player selection disables hunting and preserves its target', function()
  reset(); start(); dem.targeting.setPlayer('Aeden'); eq(dem.target,'Aeden')
  assert(not dem.hunt.enabled); cycle(); eq(#sent,1)
end)
test('manual denizen selection switches only after prior balance recovers', function()
  reset(); start(); dem.targeting.setDenizen('fido2335'); eq(dem.target,'fido2335')
  dem.onPrompt(); eq(#sent,1); cycle(); eq(sent[2],'invoke combustion 2335')
end)
test('manual bare name and ID references can switch hunting', function()
  for _, ref in ipairs({'fido','2335'}) do
    reset(); start(); dem.targeting.setDenizen(ref); cycle()
    eq(dem.target,ref); eq(sent[2],'invoke combustion 2335')
  end
end)
test('old attack kill and trailing error preserve a newly selected target', function()
  reset(); start(); dem.targeting.setDenizen('fido2335')
  dem.hunt.onKill('a warrior ant'); dem.hunt.onMissing(); roster(); cycle()
  eq(dem.target,'fido2335'); eq(sent[2],'invoke combustion 2335')
end)
test('manual override does not add a name to the area allowlist', function()
  reset(); start(); dem.targeting.setDenizen('fido'); cycle()
  dem.hunt.onKill('Fido'); roster(); cycle()
  eq(sent[3],'invoke combustion 1234')
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
  dem.onPrompt(); eq(sent[1],'invoke combustion 7')
  event('Char.Items.Remove',{location='room',item='7'}); cycle(); eq(#sent,1)
  event('Char.Items.Add',{location='room',item={id='8',name='a warrior ant',attrib='m'}})
  assert(dem.room.ready); dem.onPrompt(); eq(sent[2],'invoke combustion 8')
  roster({{id='8',name='a warrior ant',attrib='m'}})
  dem.onPrompt(); eq(sent[2],'invoke combustion 8')
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
  reset(); start(); local oldHandlers={}
  for _,h in ipairs(handlers) do oldHandlers[#oldHandlers+1]=h end
  DEMONIC_TEST_LOAD(); assert(not dem.hunt.enabled)
  for _,h in ipairs(oldHandlers) do assert(not h.active, 'reload leaked an old handler') end
  tick(20); eq(#sent,1)
end)
test('installation in an already connected idle profile requests fresh contents', function()
  reset(); vitals(); room(); roster()
  gmcpSent = {}; DEMONIC_TEST_LOAD()
  assert(not dem.hunt.enabled); assert(not dem.room.ready)
  local requested, subscribed = false, false
  for _, msg in ipairs(gmcpSent) do
    if msg == 'Char.Items.Room ""' then requested = true end
    if msg:find('Core.Supports.Add',1,true) then subscribed = true end
  end
  assert(requested and subscribed, 'install must subscribe and refresh without another game prompt')
end)
test('GMCP only roster and recovery events drive hunting without extra text', function()
  reset(); setup(); dem.hunt.toggle(); roster(); tick(0); eq(#sent,1)
  vitals({eq='0'}); tick(0); vitals(); tick(0); eq(#sent,2)
end)
test('removing an unsubmitted manual target ends its temporary exception', function()
  reset(); start(); dem.targeting.setDenizen('fido2335')
  event('Char.Items.Remove',{location='room',item='2335'}); cycle()
  assert(dem.hunt.enabled); eq(sent[2],'invoke combustion 1234')
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
test('duplicate denizen names select one and stay pinned after list reordering', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='2336',name='Fido',attrib='m'}})
  dem.targeting.setDenizen('fido'); assert(dem.hunt.enabled)
  cycle(); eq(sent[2],'invoke combustion 2335'); eq(dem.target,'fido')
  roster({{id='2336',name='Fido',attrib='m'},{id='2335',name='Fido',attrib='m'}})
  cycle(); eq(sent[3],'invoke combustion 2335')
end)
test('room synchronization timeout turns mode off rather than using a cached list', function()
  reset(); setup(); dem.hunt.toggle(); tick(11)
  assert(not dem.hunt.enabled); eq(#sent,0)
end)
test('explicit respawn arrival can revive an ID suppressed by an earlier kill', function()
  reset(); start(); dem.hunt.onKill('a warrior ant'); roster({}); cycle(); eq(#sent,1)
  event('Char.Items.Add',{location='room',item={id='1234',name='a warrior ant',attrib='m'}})
  dem.onPrompt(); eq(sent[2],'invoke combustion 1234')
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
  assert(dem.hunt.enabled); eq(sent[2],'invoke combustion 9')
end)
test('a refresh snapshot can end an override that disappeared without a delta', function()
  reset(); start(); dem.hunt.onKill('a warrior ant')
  dem.targeting.setDenizen('fido2335')
  roster({{id='9',name='a warrior ant',attrib='m'}}); cycle()
  assert(dem.hunt.enabled); eq(sent[2],'invoke combustion 9')
end)
test('a truly unknown reference selected during refresh never authorizes an attack', function()
  reset(); start(); dem.hunt.onKill('a warrior ant')
  dem.targeting.setDenizen('unknown9999'); roster(); cycle()
  assert(not dem.hunt.enabled); eq(#sent,1)
end)
test('one target alias classifies all three opaque denizen reference forms', function()
  for _, ref in ipairs({'fido','fido2335','2335'}) do
    reset(); setup(); DEMONIC_TEST_TARGET_ALIAS(ref)
    eq(dem.target,ref); eq(dem.targeting.kind,'denizen'); assert(not dem.hunt.enabled)
  end
end)
test('one target alias treats unknown names as player targets and stops hunting', function()
  reset(); start(); DEMONIC_TEST_TARGET_ALIAS('Aeden')
  eq(dem.target,'Aeden'); eq(dem.targeting.kind,'player'); assert(not dem.hunt.enabled)
  cycle(); eq(#sent,1)
end)
test('t clear dispatches through the unified alias', function()
  reset(); start(); DEMONIC_TEST_TARGET_ALIAS('clear')
  eq(dem.target,nil); assert(not dem.hunt.enabled)
end)
test('generic ant selection skips corpses and protected ants before choosing a unique ID', function()
  reset(); setup(); roster({{id='1',name='a warrior ant',attrib='md'},
    {id='2',name='an ant guard',attrib='mx'},{id='427409',name='a warrior ant',attrib='m'},
    {id='428244',name='a worker ant',attrib='m'}})
  dem.targeting.set('ant'); dem.hunt.toggle()
  roster({{id='1',name='a warrior ant',attrib='md'},{id='2',name='an ant guard',attrib='mx'},
    {id='427409',name='a warrior ant',attrib='m'},{id='428244',name='a worker ant',attrib='m'}})
  dem.onPrompt(); eq(dem.target,'ant'); eq(sent[1],'invoke combustion 427409')
  roster({{id='428244',name='a worker ant',attrib='m'},{id='427409',name='a warrior ant',attrib='m'}})
  cycle(); eq(sent[2],'invoke combustion 427409')
end)
test('generic matching works for bats and rats rather than only ants', function()
  for _, fixture in ipairs({{word='bat',first='a small vampire bat',second='a cave bat'},
    {word='rat',first='a brown rat',second='a sewer rat'}}) do
    reset(); setup(); dem.hunt.add(fixture.word); dem.hunt.toggle()
    roster({{id='7',name=fixture.first,attrib='m'},{id='8',name=fixture.second,attrib='m'}})
    dem.onPrompt(); eq(sent[1],'invoke combustion 7')
    dem.hunt.onKill(fixture.first)
    roster({{id='8',name=fixture.second,attrib='m'}}); cycle()
    eq(sent[2],'invoke combustion 8')
  end
end)
test('a generic area word matches whole words without matching giant or antenna', function()
  reset(); setup(); dem.hunt.add('ant'); dem.hunt.toggle()
  roster({{id='5',name='a giant',attrib='m'},{id='6',name='an antenna beast',attrib='m'},
    {id='9',name='a worker ant',attrib='m'}})
  dem.onPrompt(); eq(sent[1],'invoke combustion 9')
end)
test('existing full description entries do not expand to other denizen types', function()
  reset(); setup(); dem.hunt.toggle()
  roster({{id='8',name='a worker ant',attrib='m'},{id='9',name='A   WARRIOR ANT',attrib='m'}})
  dem.onPrompt(); eq(sent[1],'invoke combustion 9')
end)
test('removing a keyword preserves a selection covered by another area entry', function()
  reset(); setup(); dem.hunt.add('ant'); dem.hunt.toggle(); roster(); dem.onPrompt()
  dem.hunt.remove('ant'); cycle(); eq(sent[2],'invoke combustion 1234')
end)
test('a removed generic manual target returns to the area list instead of another override', function()
  reset(); start(); roster({{id='1234',name='a warrior ant',attrib='m'},
    {id='7',name='a cave bat',attrib='m'},{id='8',name='a vampire bat',attrib='m'}})
  dem.targeting.set('bat'); cycle(); eq(sent[2],'invoke combustion 7')
  event('Char.Items.Remove',{location='room',item='7'})
  roster({{id='1234',name='a warrior ant',attrib='m'},{id='8',name='a vampire bat',attrib='m'}}); cycle()
  eq(sent[3],'invoke combustion 1234')
end)
test('protected only references remain globally targetable but never become hunting attacks', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='9',name='a guard',attrib='mx'}})
  dem.targeting.set('guard'); eq(dem.targeting.kind,'denizen')
  assert(not dem.hunt.enabled); eq(dem.target,'guard'); cycle(); eq(#sent,1)
end)
test('an explicit protected numeric ID cannot redirect to another numeric name', function()
  reset(); setup(); roster({{id='9',name='a guard',attrib='mx'},{id='8',name='a creature named 9',attrib='m'}})
  dem.targeting.set('9'); dem.hunt.toggle(); roster({{id='9',name='a guard',attrib='mx'},
    {id='8',name='a creature named 9',attrib='m'}}); dem.onPrompt(); eq(#sent,0)
end)
test('both new missing target lines end only their submitted attack selection', function()
  for _, text in ipairs({'Nothing can be seen here by that name.',
    'Ahh, I am truly sorry, but I do not see anyone by that name here.'}) do
    reset(); start(); dem.targeting.setDenizen('fido2335')
    DEMONIC_TEST_MISSING_TARGET(text); roster(); cycle()
    eq(dem.target,'fido2335'); eq(sent[2],'invoke combustion 2335')
  end
end)
test('a generic manual exception ends when its pinned denizen becomes a corpse', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='7',name='a cave bat',attrib='m'}})
  event('Char.Items.Add',{location='room',item={id='8',name='a vampire bat',attrib='m'}})
  dem.targeting.set('bat'); cycle(); eq(sent[2],'invoke combustion 7')
  event('Char.Items.Update',{location='room',item={id='7',attrib='md'}}); cycle()
  eq(sent[3],'invoke combustion 1234')
end)
test('a protected pinned target cannot transfer its manual exception to a second match', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='7',name='a cave bat',attrib='m'}})
  event('Char.Items.Add',{location='room',item={id='8',name='a vampire bat',attrib='m'}})
  dem.targeting.set('bat'); cycle(); eq(sent[2],'invoke combustion 7')
  event('Char.Items.Update',{location='room',item={id='7',attrib='mx'}}); cycle()
  eq(#sent,2); assert(not dem.hunt.enabled); eq(dem.target,'bat')
end)
test('renaming a pinned living denizen does not redirect a generic manual target', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='7',name='a cave bat',attrib='m'}})
  event('Char.Items.Add',{location='room',item={id='8',name='a vampire bat',attrib='m'}})
  dem.targeting.set('bat'); cycle(); eq(sent[2],'invoke combustion 7')
  event('Char.Items.Update',{location='room',item={id='7',name='a changed creature'}}); cycle()
  eq(sent[3],'invoke combustion 7'); eq(dem.target,'bat')
end)
test('room info after a prompt accepts its roster without another text prompt', function()
  reset(); start(); dem.onPrompt(); room('Ant colony',102)
  roster({{id='9',name='a warrior ant',attrib='m'}})
  vitals({eq='0'}); vitals(); tick(0)
  eq(dem.room.num,'102'); eq(sent[2],'invoke combustion 9')
end)
test('room info before a prompt also accepts a full roster immediately', function()
  reset(); setup(); dem.hunt.toggle(); roster({}); tick(0)
  room('Ant colony',102); roster({{id='9',name='a warrior ant',attrib='m'}}); tick(0)
  eq(sent[1],'invoke combustion 9')
end)
test('missing roster retries GMCP once then ih once and times out at ten seconds', function()
  reset(); setup(); gmcpSent={}; dem.hunt.toggle(); tick(0)
  eq(queryCount(),1); eq(gmcpSent[#gmcpSent],'Char.Items.Room ""')
  tick(0.19); eq(queryCount(),1); eq(commandCount('ih'),0)
  tick(0.01); eq(queryCount(),1); eq(commandCount('ih'),1)
  tick(0.8); eq(queryCount(),2)
  tick(8.9); assert(dem.hunt.enabled); tick(0.1); assert(not dem.hunt.enabled)
  eq(queryCount(),2); eq(commandCount('ih'),1); eq(commandCount('look'),0); eq(#sent,0)
end)
test('duplicate refresh reasons share a request and retry budget', function()
  reset(); setup(); gmcpSent={}; dem.hunt.toggle()
  dem.room.request('duplicate one'); dem.room.request('duplicate two'); tick(0)
  eq(queryCount(),1); tick(2); eq(queryCount(),2); eq(commandCount('ih'),1)
end)
test('a valid empty room list cancels recovery timers without turning hunting off', function()
  reset(); setup(); gmcpSent={}; dem.hunt.toggle(); tick(0)
  roster({}); tick(12); assert(dem.hunt.enabled)
  eq(queryCount(),1); eq(commandCount('ih'),0); eq(#sent,0)
end)
test('inventory lists cannot satisfy a pending room refresh', function()
  reset(); setup(); dem.hunt.toggle(); tick(0)
  event('Char.Items.List',{location='inv',items={{id='9',name='a warrior ant',attrib='m'}}})
  tick(2); assert(not dem.room.ready); eq(commandCount('ih'),1); eq(#sent,0)
end)
test('removal before a kill still requests exactly one terminal reconciliation', function()
  reset(); start(); gmcpSent={}
  event('Char.Items.Remove',{location='room',item='1234'})
  dem.hunt.onKill('a warrior ant'); dem.hunt.onMissing(); tick(0)
  eq(queryCount(),1); assert(dem.room.ready)
end)
test('kill removal and trailing error coalesce even when the first reply arrives early', function()
  reset(); start(); gmcpSent={}; dem.hunt.onKill('a warrior ant'); tick(0); eq(queryCount(),1)
  roster({}); event('Char.Items.Remove',{location='room',item='1234'})
  dem.hunt.onMissing(); tick(0); eq(queryCount(),1)
end)
test('a terminal message from an older room cannot invalidate the new room', function()
  reset(); start(); send('n'); room('Ant colony',102)
  roster({{id='9',name='a warrior ant',attrib='m'}}); tick(0); gmcpSent={}
  dem.hunt.onKill('a warrior ant'); dem.hunt.onMissing(); tick(0)
  assert(dem.room.ready); eq(queryCount(),0)
end)
test('turning off hunting cancels pending retries and ih fallback', function()
  reset(); setup(); gmcpSent={}; dem.hunt.toggle(); tick(0); dem.hunt.toggle(); tick(11)
  eq(queryCount(),1); eq(commandCount('ih'),0); eq(#sent,0)
end)
test('disconnect cancels room retries and cannot reuse a late room list', function()
  reset(); setup(); gmcpSent={}; dem.hunt.toggle(); tick(0)
  raiseEvent('sysDisconnectionEvent'); roster(); tick(11)
  eq(commandCount('ih'),0); eq(queryCount(),1); assert(not dem.room.ready)
end)
test('a later room cancels the earlier room fallback deadline', function()
  reset(); setup(); dem.hunt.toggle(); tick(0); tick(0.1)
  room('Ant colony',102); roster({}); tick(12)
  eq(commandCount('ih'),0); assert(dem.hunt.enabled)
end)
test('the additional missing-target line follows the immutable submitted action', function()
  reset(); start(); dem.targeting.setDenizen('fido2335')
  DEMONIC_TEST_MISSING_TARGET('You detect nothing here by that name.')
  roster(); vitals({eq='0'}); vitals(); tick(0)
  eq(dem.target,'fido2335'); eq(sent[2],'invoke combustion 2335')
end)
test('hunt status reports pending room recovery details', function()
  reset(); setup(); dem.hunt.toggle(); tick(1); messages={}; dem.hunt.status(true)
  local output=table.concat(messages,' '):lower()
  assert(output:find('refresh',1,true)); assert(output:find('age',1,true))
  assert(output:find('retry',1,true)); assert(output:find('ih',1,true))
  assert(output:find('hunt mode enabled',1,true), 'status must retain the initiating refresh reason')
end)
test('a full roster arriving after ih resumes without any text prompt', function()
  reset(); setup(); dem.hunt.toggle(); tick(2); eq(commandCount('ih'),1); eq(#sent,0)
  roster({{id='9',name='a warrior ant',attrib='m'}}); tick(0)
  eq(sent[1],'invoke combustion 9'); assert(dem.room.ready)
end)
test('reloading with a pending refresh cannot fire an old ih fallback', function()
  reset(); setup(); dem.hunt.toggle(); tick(0); DEMONIC_TEST_LOAD(); tick(12)
  assert(not dem.hunt.enabled); eq(commandCount('ih'),0); eq(#sent,0)
end)
test('two confirmed movements can return to the original room', function()
  reset(); start(); send('n&&s'); room('Ant colony',102)
  vitals({eq='0'}); vitals(); tick(0); eq(#sent,1)
  room('Ant colony',101); roster(); tick(0)
  eq(sent[2],'invoke combustion 1234'); eq(dem.room.num,'101')
end)
test('ordinary hunt status contains only mode target and a short reason', function()
  reset(); setup(); dem.hunt.toggle(); messages={}; DEMONIC_TEST_HUNT_STATUS(false)
  local output=table.concat(messages,' '):lower()
  assert(output:find('on',1,true)); assert(output:find('target:',1,true)); assert(output:find('waiting',1,true))
  for _, verbose in ipairs({'hp:','mp:','retry:','request age:','equilibrium:','refresh reason:'}) do
    assert(not output:find(verbose,1,true), 'ordinary status must omit '..verbose)
  end
end)
test('debug status still exposes diagnostic information through the actual alias', function()
  reset(); setup(); dem.hunt.toggle(); messages={}; DEMONIC_TEST_HUNT_STATUS(true)
  local output=table.concat(messages,' '):lower()
  assert(output:find('hp:',1,true)); assert(output:find('request age:',1,true)); assert(output:find('retry:',1,true))
end)
test('the unified alias waits instead of selecting a player while room identity is unconfirmed', function()
  reset(); setup(); dem.hunt.toggle(); roster({}); tick(0); room('Ant colony',102)
  DEMONIC_TEST_TARGET_ALIAS('ant'); eq(dem.target,'ant'); eq(dem.targeting.kind,'pending'); assert(dem.hunt.enabled)
  roster({{id='9',name='a warrior ant',attrib='m'}}); tick(0)
  eq(dem.targeting.kind,'denizen'); eq(dem.target,'ant'); eq(sent[1],'invoke combustion 9')
end)

test('a pending manual denizen preserves the submitted attack and resolves its next target', function()
  reset(); start(); local action=dem.balances.action; dem.room.request('refresh')
  DEMONIC_TEST_TARGET_ALIAS('fido2335'); tick(0)
  eq(dem.targeting.kind,'pending'); assert(dem.hunt.enabled); eq(dem.balances.action,action); eq(#sent,1)
  roster(); tick(0); eq(dem.targeting.kind,'denizen'); eq(dem.balances.action,action); eq(#sent,1)
  cycle(); eq(sent[2],'invoke combustion 2335')
end)

test('a pending player is classified only after the current full roster arrives', function()
  reset(); setup(); dem.hunt.toggle(); DEMONIC_TEST_TARGET_ALIAS('Aeden'); tick(0)
  eq(dem.targeting.kind,'pending'); assert(dem.hunt.enabled); eq(#sent,0)
  roster(); tick(0); eq(dem.targeting.kind,'player'); eq(dem.target,'Aeden'); assert(not dem.hunt.enabled); eq(#sent,0)
end)

test('pending references resolve while hunting is off and do not enable it', function()
  reset(); DEMONIC_TEST_TARGET_ALIAS('fido'); eq(dem.targeting.kind,'pending')
  room(); roster(); tick(0)
  eq(dem.targeting.kind,'denizen'); eq(dem.target,'fido'); assert(not dem.hunt.enabled); eq(#sent,0)
end)

test('a roster followed immediately by its prompt resolves a pending target before hunting', function()
  reset(); setup(); dem.hunt.toggle(); DEMONIC_TEST_TARGET_ALIAS('fido')
  roster(); dem.onPrompt(); tick(0)
  eq(dem.targeting.kind,'denizen'); eq(dem.target,'fido'); eq(sent[1],'invoke combustion 2335')
end)

test('pending targeting while hunt is off reissues contents after an early roster was ignored', function()
  reset(); DEMONIC_TEST_TARGET_ALIAS('fido'); eq(queryCount(),1)
  roster(); room(); eq(queryCount(),2)
  roster(); dem.onPrompt(); tick(0)
  eq(dem.targeting.kind,'denizen'); eq(dem.target,'fido'); assert(not dem.hunt.enabled); eq(#sent,0)
end)

test('pending targeting subscribes to room GMCP even before hunting has been enabled', function()
  reset(); DEMONIC_TEST_TARGET_ALIAS('fido')
  local subscribed=false
  for _, request in ipairs(gmcpSent) do
    if request:find('Core.Supports.Add',1,true) and request:find('"Room 1"',1,true)
        and request:find('"Char.Items 1"',1,true) and request:find('"IRE.Target 1"',1,true) then subscribed=true end
  end
  assert(subscribed,'target classification must subscribe before requesting its first room roster')
end)

test('a later movement cancels a pending reference from the previous context', function()
  reset(); setup(); dem.hunt.toggle(); DEMONIC_TEST_TARGET_ALIAS('fido'); eq(dem.targeting.kind,'pending')
  send('n'); room('Ant colony',102)
  roster({{id='9',name='a warrior ant',attrib='m'},{id='2335',name='Fido',attrib='m'}}); tick(0)
  assert(dem.hunt.enabled); eq(dem.target,'9'); eq(sent[1],'invoke combustion 9')
end)

test('replacing a pending reference cannot resolve an older player selection', function()
  reset(); setup(); dem.hunt.toggle(); DEMONIC_TEST_TARGET_ALIAS('Aeden'); DEMONIC_TEST_TARGET_ALIAS('ant')
  roster(); tick(0); assert(dem.hunt.enabled); eq(dem.target,'ant'); eq(sent[1],'invoke combustion 1234')
end)

test('clearing a pending reference prevents late roster resolution', function()
  reset(); setup(); dem.hunt.toggle(); DEMONIC_TEST_TARGET_ALIAS('fido'); DEMONIC_TEST_TARGET_ALIAS('clear')
  roster(); tick(0); eq(dem.target,nil); eq(dem.targeting.kind,nil); assert(not dem.hunt.enabled); eq(#sent,0)
end)

test('explicit player selection cancels pending automatic classification immediately', function()
  reset(); setup(); dem.hunt.toggle(); DEMONIC_TEST_TARGET_ALIAS('ant'); dem.targeting.setPlayer('Aeden')
  roster(); tick(0); eq(dem.target,'Aeden'); eq(dem.targeting.kind,'player'); assert(not dem.hunt.enabled); eq(#sent,0)
end)

test('connection changes cancel pending classification before later room data', function()
  reset(); setup(); dem.hunt.toggle(); DEMONIC_TEST_TARGET_ALIAS('fido'); raiseEvent('sysDisconnectionEvent')
  room(); roster(); tick(0); eq(dem.target,nil); eq(dem.targeting.kind,nil); assert(not dem.hunt.enabled)
end)

test('scaled short prompts cannot overwrite adopted GMCP resource pairs', function()
  reset(); start(); local action=dem.balances.action
  dem.onPrompt('Health:363 Mana:342 (eb)'); dem.onPrompt('Health:363 Mana:342 (eb)')
  eq(dem.vitals.hp,3998); eq(dem.vitals.mp,4459); assert(dem.hunt.enabled); eq(dem.balances.action,action)
end)

test('text zero and conflicting full prompts cannot manufacture death after GMCP adoption', function()
  reset(); start(); local generation=dem.room.generation
  dem.onPrompt('Health:0 Mana:0 (eb)'); dem.onPrompt('H:0/363 M:0/433 (eb)')
  eq(dem.vitals.hp,3998); eq(dem.vitals.maxhp,3998); assert(dem.hunt.enabled); eq(dem.room.generation,generation)
end)

test('first partial GMCP adoption invalidates a text derived resource partner', function()
  reset(); dem.onPrompt('H:312/363 M:331/433 (eb)')
  eq(dem.vitals.hp,312); eq(dem.vitals.maxhp,363)
  event('Char.Vitals',{maxhp='3998'}); eq(dem.vitals.hp,nil); eq(dem.vitals.maxhp,3998)
  dem.onPrompt('Health:363 Mana:400 (eb)'); eq(dem.vitals.hp,nil); eq(dem.vitals.mp,400)
  event('Char.Vitals',{hp='3998',mp='4567'}); eq(dem.vitals.hp,3998); eq(dem.vitals.maxmp,nil)
  event('Char.Vitals',{maxmp='4772'}); dem.onPrompt('H:1/1 M:2/2 (eb)')
  eq(dem.vitals.hp,3998); eq(dem.vitals.maxhp,3998); eq(dem.vitals.mp,4567); eq(dem.vitals.maxmp,4772)
end)

test('malformed GMCP adopts authority and text cannot repair unknown resource values', function()
  reset(); dem.onPrompt('H:312/363 M:331/433 (eb)'); event('Char.Vitals',{hp='bad'})
  dem.onPrompt('H:363/363 M:433/433 (eb)'); eq(dem.vitals.hp,nil); eq(dem.vitals.maxhp,nil)
  event('Char.Vitals',{hp='3998',maxhp='3998'}); dem.onPrompt('Health:1 Mana:433 (eb)')
  eq(dem.vitals.hp,3998); eq(dem.vitals.maxhp,3998)
end)

test('connection reset clears resource authority and restores text only fallback', function()
  reset(); vitals(); raiseEvent('sysDisconnectionEvent'); dem.onPrompt('H:312/363 M:331/433 (eb)')
  eq(dem.vitals.hp,312); eq(dem.vitals.maxhp,363); eq(dem.vitals.mp,331); eq(dem.vitals.maxmp,433)
end)

test('death clears the reported room and revival accepts room 13359 without enabling hunt', function()
  reset(); start(); room('Ant colony',102); DEMONIC_TEST_TARGET_ALIAS('ant')
  vitals({hp='0'}); eq(dem.balances.action,nil); eq(dem.target,nil); eq(dem.room.num,nil)
  eq(dem.balances.bal,nil); eq(dem.balances.eq,nil); assert(not dem.hunt.enabled)
  vitals(); room('Revival courtyard',13359); roster(); tick(0)
  eq(dem.room.num,'13359'); assert(dem.room.ready); assert(not dem.hunt.enabled); eq(#sent,1)
end)

test('death cleanup runs once and preserves resource authority until fresh revival data', function()
  reset(); start(); vitals({hp='0'}); local generation=dem.room.generation
  vitals({hp='0'}); eq(dem.room.generation,generation)
  dem.onPrompt('Health:363 Mana:433 (eb)'); eq(dem.vitals.hp,0); assert(dem.balances.dead); assert(not dem.hunt.enabled)
  event('Char.Vitals',{bal='1',eq='1'}); assert(dem.balances.dead)
  vitals(); assert(not dem.balances.dead); assert(not dem.hunt.enabled)
end)

test('an explicit death signal remains latched across unrelated partial vital packets', function()
  reset(); start(); event('Char.Vitals',{dead='1'})
  local generation=dem.room.generation; assert(dem.balances.dead)
  event('Char.Vitals',{bal='1'}); eq(dem.room.generation,generation); assert(dem.balances.dead)
  assert(not dem.hunt.toggle()); assert(not dem.hunt.enabled)
  event('Char.Vitals',{dead='0',hp='3998'}); assert(not dem.balances.dead); assert(not dem.hunt.enabled)
end)

test('a divine grace refusal retires only the unexecuted action without granting readiness', function()
  reset(); start(); local action=dem.balances.action
  DEMONIC_TEST_GRACE()
  eq(dem.balances.action,nil); eq(dem.balances.eq,false); assert(not dem.hunt.enabled)
  eq(action.key,'1234'); eq(action.reference,'1234'); eq(commandCount('renounce grace'),0)
  vitals(); tick(11); eq(#sent,1)
end)

test('an explicit refusal arriving after hunt stops still releases its unexecuted action', function()
  reset(); start(); dem.hunt.stop(); dem.hunt.onAttackRejected('Divine grace prevents attacks.')
  eq(dem.balances.action,nil); assert(not dem.hunt.enabled); eq(#sent,1)
end)

test('an accepted balance cycle is preserved when an attack refusal is ambiguous', function()
  reset(); start(); vitals({eq='0'}); local action=dem.balances.action
  dem.hunt.onAttackRejected('Divine grace prevents attacks.')
  eq(dem.balances.action,action); assert(not dem.hunt.enabled)
  vitals(); eq(dem.balances.action,nil); eq(#sent,1)
end)

test('manual restart after grace removal cannot inherit the rejected attack watchdog', function()
  reset(); start(); dem.hunt.onAttackRejected('Divine grace prevents attacks.')
  vitals({eq='0'}); tick(11); vitals(); dem.hunt.toggle(); roster(); tick(0)
  assert(dem.hunt.enabled); eq(sent[2],'invoke combustion 1234')
end)

test('GMCP only outgoing directions leave the reported roster usable', function()
  reset(); start(); send('n&&e'); cycle(); eq(sent[2],'invoke combustion 1234')
  eq(dem.room.num,'101'); assert(dem.room.ready)
end)

test('GMCP only mob removal keeps remaining roster ready', function()
  reset(); start(); event('Char.Items.Remove',{location='room',item='1234'})
  assert(dem.room.ready); eq(dem.room.items['1234'],nil)
end)

test('a background refresh preserves readiness and cannot stop usable hunting', function()
  reset(); setup(); dem.hunt.toggle(); roster({}); tick(0)
  dem.room.request('background reconciliation',false); assert(dem.room.ready)
  tick(10); assert(dem.hunt.enabled); assert(dem.room.ready)
  assert(dem.room.diagnostics().refreshError)
end)

test('background reconciliation does not postpone the next balanced attack', function()
  reset(); start(); dem.hunt.add('fido'); vitals({eq='0'})
  event('Char.Items.Remove',{location='room',item='1234'}); vitals(); tick(0)
  eq(sent[2],'invoke combustion 2335'); assert(dem.room.ready)
end)

test('reported identity overrides cached exit predictions without walk text', function()
  reset(); setup(); event('Room.Info',{num=101,area='Ant colony',exits={n=102}})
  dem.hunt.toggle(); roster({}); send('n'); room('Ant colony',900)
  roster(); tick(0); eq(dem.room.num,'900'); eq(sent[1],'invoke combustion 1234')
end)

test('late duplicate terminal text cannot retire a same named successor', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='9',name='a warrior ant',attrib='m'}})
  vitals({eq='0'}); event('Char.Items.Remove',{location='room',item='1234'})
  dem.hunt.onKill('a warrior ant'); vitals(); tick(0); eq(sent[2],'invoke combustion 9')
  dem.hunt.onKill('a warrior ant'); dem.hunt.onMissing(); tick(0)
  assert(not dem.room.retired['9']); eq(dem.target,'9'); assert(dem.room.ready)
  event('Char.Items.Remove',{location='room',item='9'}); assert(dem.room.retired['9'])
end)

test('an ambiguous kill can reconcile again after an earlier harmless snapshot', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='9',name='a warrior ant',attrib='m'}})
  vitals({eq='0'}); event('Char.Items.Remove',{location='room',item='1234'}); vitals(); tick(0)
  eq(sent[2],'invoke combustion 9'); gmcpSent={}
  dem.hunt.onKill('a warrior ant'); roster({{id='9',name='a warrior ant',attrib='m'}})
  gmcpSent={}; dem.hunt.onKill('a warrior ant'); eq(queryCount(),1)
  roster({}); assert(dem.balances.action.retired); assert(dem.room.ready)
end)

test('late missing text cannot retire a differently named successor', function()
  reset(); start(); dem.hunt.add('fido'); vitals({eq='0'}); dem.hunt.onKill('a warrior ant')
  vitals(); tick(0); eq(sent[2],'invoke combustion 2335')
  dem.hunt.onMissing(); tick(0); assert(not dem.room.retired['2335']); eq(dem.target,'2335')
  dem.hunt.onKill('Fido'); assert(dem.room.retired['2335'])
end)

test('background refresh upgrades to blocking without renewing its recovery budget', function()
  reset(); setup(); dem.hunt.toggle(); roster({}); gmcpSent={}
  dem.room.request('background',false); local refresh=dem.room.refresh; tick(0.15)
  dem.room.request('required',true); eq(dem.room.refresh,refresh); assert(not dem.room.ready)
  dem.room.request('cannot downgrade',false); assert(refresh.blocking)
  tick(0.05); eq(commandCount('ih'),1); tick(0.8); eq(queryCount(),2)
  tick(9); assert(not dem.hunt.enabled)
end)

test('duplicate same room info preserves roster context and target', function()
  reset(); start(); local context,generation=dem.room.contextId,dem.room.generation
  gmcpSent={}; room(); tick(0)
  eq(dem.room.contextId,context); eq(dem.room.generation,generation)
  assert(dem.room.ready); eq(dem.target,'1234'); eq(queryCount(),0); eq(#sent,1)
end)

test('a list before changed identity is cleared instead of reused for the new room', function()
  reset(); setup(); dem.hunt.toggle(); roster({}); tick(0)
  roster({{id='7',name='a warrior ant',attrib='m'}}); room('Ant colony',102); tick(0)
  assert(not dem.room.ready); eq(dem.room.items['7'],nil); eq(#sent,0)
  roster({{id='8',name='a warrior ant',attrib='m'}}); tick(0); eq(sent[1],'invoke combustion 8')
end)

test('balance and direction refusals cannot invalidate a reported room', function()
  reset(); setup(); local context,generation=dem.room.contextId,dem.room.generation
  send('north'); event('Room.WrongDir','north'); DEMONIC_TEST_UNAVAILABLE('bal')
  DEMONIC_TEST_UNAVAILABLE('eq'); eq(dem.room.num,'101'); assert(dem.room.ready)
  eq(dem.room.contextId,context); eq(dem.room.generation,generation)
  eq(dem.balances.bal,false); eq(dem.balances.eq,false)
end)

test('debug status shows roster and refresh mode without movement prediction', function()
  reset(); setup(); dem.hunt.toggle(); roster({}); dem.room.request('background',false)
  messages={}; DEMONIC_TEST_HUNT_STATUS(true); local output=table.concat(messages,' '):lower()
  assert(output:find('roster:',1,true)); assert(output:find('background',1,true))
  for _,label in ipairs({'pending movements','expected room','blocking direction','identity block'}) do
    assert(not output:find(label,1,true))
  end
end)

test('unknown identity ignores lists and deltas until real room info arrives', function()
  reset(); vitals(); dem.hunt.toggle(); roster()
  event('Char.Items.Add',{location='room',item={id='7',name='a warrior ant',attrib='m'}})
  tick(0); eq(dem.room.num,nil); eq(next(dem.room.items),nil); assert(not dem.room.ready)
  room(); assert(not dem.room.ready); dem.hunt.add('ant'); roster(); tick(0)
  eq(sent[1],'invoke combustion 1234')
end)

test('unknown identity times out once without inferring a room from ih contents', function()
  reset(); vitals(); dem.hunt.toggle(); tick(0.2); roster(); tick(9.8)
  assert(not dem.hunt.enabled); eq(dem.room.num,nil); eq(commandCount('ih'),1); eq(#sent,0)
end)

test('rapid reported room changes cancel the intermediate roster and timers', function()
  reset(); setup(); dem.hunt.toggle(); roster({}); tick(0)
  room('Ant colony',102); roster({{id='7',name='a warrior ant',attrib='m'}})
  room('Ant colony',103); tick(0); eq(#sent,0); eq(dem.room.items['7'],nil)
  roster({{id='8',name='a warrior ant',attrib='m'}}); tick(0)
  eq(sent[1],'invoke combustion 8'); tick(2); eq(commandCount('ih'),0)
end)

test('inventory deltas cannot remove or reclassify a known room mob', function()
  reset(); setup()
  event('Char.Items.Remove',{location='inv',item='1234'})
  event('Char.Items.Update',{location='rep123',item={id='1234',attrib='md'}})
  assert(dem.room.eligible(dem.room.items['1234'])); assert(dem.room.ready)
end)

test('an actual slain trigger retires its ID and preserves readiness for another mob', function()
  reset(); start(); dem.hunt.add('fido'); vitals({eq='0'})
  DEMONIC_TEST_KILL('a warrior ant'); eq(dem.room.items['1234'],nil); assert(dem.room.ready)
  eq(#sent,1); vitals(); tick(0); eq(sent[2],'invoke combustion 2335')
end)

test('background refresh timers are cancelled when hunt is stopped', function()
  reset(); setup(); dem.hunt.toggle(); roster({}); gmcpSent={}
  dem.room.request('background',false); dem.hunt.stop(); tick(11)
  eq(queryCount(),1); eq(commandCount('ih'),0); assert(dem.room.ready)
end)

test('idle pending targeting never sends timed ih while hunt is off', function()
  reset(); DEMONIC_TEST_TARGET_ALIAS('fido'); tick(11)
  eq(queryCount(),1); eq(commandCount('ih'),0); assert(not dem.hunt.enabled)
end)

test('grace restart preserves same name terminal provenance', function()
  reset(); start(); event('Char.Items.Add',{location='room',item={id='9',name='a warrior ant',attrib='m'}})
  vitals({eq='0'}); event('Char.Items.Remove',{location='room',item='1234'})
  dem.hunt.onKill('a warrior ant'); vitals(); tick(0); eq(sent[2],'invoke combustion 9')
  DEMONIC_TEST_GRACE(); eq(dem.hunt.lastAction,nil)
  vitals(); dem.hunt.toggle(); roster({{id='9',name='a warrior ant',attrib='m'}}); tick(0)
  eq(sent[3],'invoke combustion 9'); DEMONIC_TEST_KILL('a warrior ant')
  assert(not dem.room.retired['9']); assert(dem.room.items['9']); eq(dem.target,'9')
end)

test('grace restart preserves untagged missing target provenance', function()
  reset(); start(); dem.hunt.add('fido'); vitals({eq='0'}); dem.hunt.onKill('a warrior ant')
  vitals(); tick(0); eq(sent[2],'invoke combustion 2335'); DEMONIC_TEST_GRACE()
  vitals(); dem.hunt.toggle(); roster({{id='2335',name='Fido',attrib='m'}}); tick(0)
  eq(sent[3],'invoke combustion 2335'); DEMONIC_TEST_MISSING_TARGET('You detect nothing here by that name.')
  assert(not dem.room.retired['2335']); assert(dem.room.items['2335']); eq(dem.target,'2335')
end)

for _,packet in ipairs({'update','list'}) do
  test('a renamed prior target cannot consume its same named successor via '..packet, function()
    reset(); start(); dem.hunt.add('fido'); vitals({eq='0'})
    if packet=='update' then
      event('Char.Items.Update',{location='room',item={id='1234',name='Fido'}})
    else
      roster({{id='1234',name='Fido',attrib='m'},{id='2335',name='Fido',attrib='m'}})
    end
    event('Char.Items.Remove',{location='room',item='1234'}); vitals(); tick(0)
    eq(sent[2],'invoke combustion 2335'); DEMONIC_TEST_KILL('Fido')
    assert(not dem.room.retired['2335']); assert(dem.room.items['2335']); eq(dem.target,'2335')
  end)
end

test('observed aliases can make an already submitted successor kill ambiguous', function()
  reset(); start(); dem.targeting.setDenizen('fido'); cycle(); eq(sent[2],'invoke combustion 2335')
  event('Char.Items.Update',{location='room',item={id='1234',name='Fido'}})
  DEMONIC_TEST_KILL('Fido'); assert(not dem.room.retired['2335']); eq(dem.target,'fido')
end)

test('exported startup supports actual prompt and Hunt aliases after reload', function()
  reset(); DEMONIC_TEST_PROMPT(); DEMONIC_TEST_HUNT_ALIAS(); tick(0)
  assert(dem.hunt.enabled); DEMONIC_TEST_LOAD(); DEMONIC_TEST_PROMPT()
  assert(not dem.hunt.enabled)
end)

test('maintenance tracks wrapped Arctar and Summoner confirmations', function()
  reset(); vitals(); dem.defences.toggle(); dem.onPrompt()
  eq(commands[1], 'summon arctar')
  local action = dem.balances.action
  DEMONIC_TEST_DEFENCE_LOG('arctar-summon')
  eq(dem.defences.active.arctar, true)
  dem.balances.recovered('bal'); dem.onPrompt(); eq(dem.balances.action, action)
  cycle(); eq(commands[2], 'invoke warmth')
  for i, name in ipairs({'warmth', 'astralvision', 'distortion-up', 'mindseye-up'}) do
    DEMONIC_TEST_DEFENCE_LOG(name); dem.onPrompt(); eq(#commands, i+1)
    dem.onPrompt('Health:3998 Mana:4459 (eb)')
  end
  eq(dem.defences.active.warmth, true); eq(dem.defences.active.astralvision, true)
  eq(dem.defences.active.distortion, true); eq(dem.defences.active.mindseye, true)
  DEMONIC_TEST_DEFENCE_LOG('distortion-down')
  DEMONIC_TEST_DEFENCE_LOG('arctar-banish')
  eq(dem.defences.active.distortion, false); eq(dem.defences.active.arctar, false)
  dem.onPrompt(); eq(commands[6], 'summon arctar')
end)

local function confirmArctar()
  DEMONIC_TEST_DEFENCE_LOG('arctar-summon')
  cycle()
end

test('maintenance pauses for Hunt and resumes without competing sends', function()
  reset(); setup(); dem.defences.toggle(); dem.onPrompt()
  local count=#commands
  DEMONIC_TEST_HUNT_ALIAS(); roster(); dem.onPrompt(); eq(#commands,count)
  confirmArctar(); eq(sent[#sent],'invoke combustion 1234')
  local traces=#sent
  DEMONIC_TEST_HUNT_ALIAS(); cycle()
  eq(#sent,traces); eq(commands[#commands],'invoke warmth'); assert(dem.defences.enabled)
end)

test('maintenance off preserves a pending action and prevents further defence casts', function()
  reset(); vitals(); dem.defences.toggle(); dem.onPrompt()
  dem.defences.toggle(); local count=#commands
  confirmArctar(); dem.onPrompt(); tick(11)
  eq(#commands,count); assert(not dem.defences.enabled); eq(dem.balances.action,nil)
end)

test('unconfirmed defence times out without retrying or allowing competing attacks', function()
  reset(); setup(); dem.defences.toggle(); dem.onPrompt()
  local count=#commands
  tick(11); assert(not dem.defences.enabled); dem.onPrompt(); eq(#commands,count)
  DEMONIC_TEST_HUNT_ALIAS(); roster(); dem.onPrompt(); eq(#sent,0)
end)

test('maintenance respects safety gates and resets on death connection and reload', function()
  for _,block in ipairs({'bal','eq','prone','stunned'}) do
    reset(); vitals({[block]=(block=='bal' or block=='eq') and '0' or '1'})
    dem.defences.toggle(); dem.onPrompt(); eq(#commands,0)
    vitals(); dem.onPrompt(); eq(commands[1],'summon arctar')
  end
  for _,kind in ipairs({'death','connection','reload'}) do
    reset(); vitals(); dem.defences.toggle(); dem.onPrompt()
    if kind=='death' then vitals({hp='0'})
    elseif kind=='connection' then raiseEvent('sysDisconnectionEvent')
    else DEMONIC_TEST_LOAD() end
    assert(not dem.defences.enabled); local count=#commands; tick(11); dem.onPrompt(); eq(#commands,count)
  end
end)

test('Arctar shields below the health stop and resumes attacks only above forty', function()
  for _, hp in ipairs({'40','30','1'}) do
    reset(); setup(); vitals({hp=hp,maxhp='100'}); dem.hunt.toggle(); roster(); dem.onPrompt()
    eq(sent[1], 'unleash arctar at me')
    DEMONIC_TEST_DEFENCE_LOG('arctar-shield')
    dem.onPrompt('Health:40 Mana:4459 (eb)'); eq(dem.balances.action, nil)
    DEMONIC_TEST_DEFENCE_LOG('arctar-ready')
    DEMONIC_TEST_DEFENCE_LOG('unleash-ready')
    vitals({hp='40',maxhp='100'}); dem.onPrompt(); eq(#sent,1)
    vitals({hp='41',maxhp='100'}); dem.onPrompt(); eq(sent[2], 'invoke combustion 1234')
  end
end)

test('a refused self-shield leaves the attacked denizen and its history intact', function()
  reset(); start(); local attack=dem.hunt.lastAction
  assert(dem.targeting.setDenizen('ant'))
  vitals({hp='40',maxhp='100',eq='0'}); dem.onPrompt(); eq(#sent,1)
  vitals({hp='40',maxhp='100'}); dem.onPrompt()
  eq(sent[2], 'unleash arctar at me'); eq(dem.target,'ant'); eq(dem.hunt.lastAction,attack)
  DEMONIC_TEST_MISSING_TARGET('You detect nothing here by that name.')
  DEMONIC_TEST_MISSING_TARGET('You detect nothing here by that name.')
  assert(not dem.hunt.enabled); assert(not dem.room.retired['1234'])
  eq(dem.target,'ant'); eq(dem.hunt.lastAction,attack); eq(dem.balances.action,nil)
end)

test('Arctar does not require a room roster or a resolved hunting target', function()
  reset(); vitals({hp='40',maxhp='100'}); dem.hunt.toggle(); dem.onPrompt()
  eq(sent[1], 'unleash arctar at me')
end)

test('low health uses the tattoo if Arctar is too expensive, subject to the mana stop', function()
  reset(); setup(); vitals({hp='40',maxhp='100',mp='17',maxmp='100'})
  dem.hunt.toggle(); roster(); dem.onPrompt(); eq(sent[1], 'touch shield')
  local action = dem.balances.action
  DEMONIC_TEST_DEFENCE_LOG('tattoo-shield')
  dem.balances.recovered('bal'); dem.onPrompt(); eq(dem.balances.action,action)
  dem.balances.recovered('eq'); dem.onPrompt(); eq(dem.balances.action,nil); eq(#sent,1)
  for _, override in ipairs({{mp='10',maxmp='100'},{eq='0'},{prone='1'},{stunned='1'}}) do
    reset(); setup(); override.hp='40'; override.maxhp='100'; vitals(override)
    dem.hunt.toggle(); roster(); dem.onPrompt(); eq(#sent,0)
    eq(dem.hunt.enabled,override.mp==nil)
  end
end)

test('the other cooldown still blocks Arctar after a Hunt restart', function()
  reset(); setup(); vitals({hp='40',maxhp='100'}); dem.hunt.toggle(); roster(); dem.onPrompt()
  DEMONIC_TEST_DEFENCE_LOG('arctar-shield')
  dem.onPrompt('Health:40 Mana:4459 (eb)')
  dem.hunt.stop(); DEMONIC_TEST_DEFENCE_LOG('shield-down'); DEMONIC_TEST_DEFENCE_LOG('arctar-ready')
  assert(dem.defences.cooldowns.unleash and not dem.defences.cooldowns.arctar)
  tick(41); dem.hunt.toggle(); roster(); dem.onPrompt(); eq(sent[2], 'touch shield')
end)

test('missing shield character data cannot continually postpone its state watchdog', function()
  reset(); setup(); vitals({hp='40',maxhp='100',maxmp='bad'})
  dem.hunt.toggle(); roster(); dem.onPrompt()
  for _=1,9 do tick(1); dem.onPrompt() end
  tick(1); assert(not dem.hunt.enabled)
end)

test('unconfirmed protection times out without repeating', function()
  reset(); vitals({hp='40',maxhp='100'}); dem.onPrompt(); eq(#sent,0)
  dem.hunt.toggle(); dem.onPrompt(); eq(sent[1], 'unleash arctar at me')
  tick(10); assert(not dem.hunt.enabled); eq(#sent,1)
end)

test('pending defence recovery gates emergency shielding', function()
  reset(); setup(); dem.defences.toggle(); dem.onPrompt()
  eq(commands[#commands],'summon arctar')
  vitals({hp='40',maxhp='100'}); dem.hunt.toggle(); roster(); dem.onPrompt(); eq(#sent,0)
  dem.balances.taken('eq'); dem.balances.recovered('eq'); dem.onPrompt(); eq(#sent,0)
  DEMONIC_TEST_DEFENCE_LOG('arctar-summon'); dem.onPrompt()
  eq(sent[1],'unleash arctar at me'); assert(dem.defences.enabled)
end)

test('defence maintenance does not cast with low mana or malformed resources', function()
  reset(); vitals({mp='10',maxmp='100'}); dem.defences.toggle(); dem.onPrompt()
  assert(not dem.defences.enabled); eq(#commands,0)
  reset(); vitals({mp='bad'}); dem.defences.toggle(); dem.onPrompt(); eq(#commands,0)
end)

test('defence confirmation cannot reuse cached readiness or a partial GMCP update', function()
  for _,fresh in ipairs({'neither','bal','eq'}) do
    reset(); vitals(); dem.onPrompt('Health:3998 Mana:4459 (eb)')
    DEMONIC_TEST_DEFENCE_LOG('arctar-summon')
    dem.defences.toggle(); dem.onPrompt(); eq(commands[1],'invoke warmth')
    local action=dem.balances.action
    DEMONIC_TEST_DEFENCE_LOG('warmth')
    local packet={hp='3998'}
    if fresh~='neither' then packet[fresh]='1' end
    event('Char.Vitals',packet); dem.onPrompt('Health:3998 Mana:4459')
    eq(#commands,1); eq(dem.balances.action,action)
    -- The missing readiness must be observed after the command, rather than cached.
    if fresh=='neither' then event('Char.Vitals',{bal='1',eq='1'})
    elseif fresh=='bal' then event('Char.Vitals',{eq='1'})
    else event('Char.Vitals',{bal='1'}) end
    dem.onPrompt('Health:3998 Mana:4459')
    eq(commands[2],'invoke astralvision'); eq(#commands,2)
  end
end)

test('ddef runs every defence from the compact prompt without toggling off or requiring success text', function()
  reset(); dem.onPrompt('Health:363 Mana:372 (eb)')
  DEMONIC_TEST_DEFS_ALIAS(); tick(0); eq(commands[1],'summon arctar')
  DEMONIC_TEST_DEFS_ALIAS(); tick(0); eq(#commands,1); assert(dem.defences.enabled)
  local expected={'invoke warmth','invoke astralvision','invoke distortion','touch mindseye'}
  for i,command in ipairs(expected) do
    dem.onPrompt('Health:363 Mana:372 (eb)'); eq(commands[i+1],command); eq(#commands,i+1)
  end
  dem.onPrompt('Health:363 Mana:372 (eb)'); eq(#commands,5); assert(not dem.defences.enabled)
  DEMONIC_TEST_DEFS_ALIAS(); tick(0); eq(commands[6],'summon arctar')
end)

test('manual defence pass waits for fresh readiness and respects observed incapacitation', function()
  reset(); dem.onPrompt('Health:363 Mana:372 (eb)'); DEMONIC_TEST_DEFS_ALIAS(); tick(0)
  dem.onPrompt('Health:363 Mana:372'); eq(#commands,1)
  dem.onPrompt('Health:363 Mana:372 (e-)'); eq(#commands,1)
  dem.onPrompt('Health:363 Mana:372 (eb)'); eq(commands[2],'invoke warmth')
  reset(); vitals({stunned='1'}); DEMONIC_TEST_DEFS_ALIAS(); tick(0); eq(#commands,0)
  vitals(); dem.onPrompt(); tick(0); eq(commands[1],'summon arctar')
end)

test('manual defence pass does not treat partial GMCP as a fresh ready prompt', function()
  reset(); vitals(); dem.onPrompt(); DEMONIC_TEST_DEFS_ALIAS(); tick(0)
  eq(commands[1],'summon arctar')
  event('Char.Vitals',{hp='3998',bal='1'}); dem.onPrompt('Health:363 Mana:372'); eq(#commands,1)
  event('Char.Vitals',{eq='1'}); dem.onPrompt('Health:363 Mana:372'); eq(commands[2],'invoke warmth')
end)

test('manual defence pass pauses during Hunt and death cancels the remaining sequence', function()
  reset(); start(); DEMONIC_TEST_DEFS_ALIAS(); tick(0); eq(#sent,1)
  assert(dem.defences.reason:find('Paused'))
  dem.hunt.stop(); cycle(); eq(commands[#commands],'summon arctar')
  local count=#commands
  vitals({hp='0'}); dem.onPrompt(); tick(11); eq(#commands,count); assert(not dem.defences.enabled)
  DEMONIC_TEST_DEFS_ALIAS(); tick(0); eq(#commands,count)
end)

test('disabled Diabolist handlers cannot change Summoner state', function()
  reset()
  DEMONIC_TEST_CLASS_TRIGGER('Vitality activated')
  DEMONIC_TEST_CLASS_TRIGGER('Wraith materialised')
  eq(dem.profession, 'summoner')
  eq(dem.defences.active.vitality, nil); eq(dem.nightfall, nil)
end)

test('health requests the pinned ID once and exposes live percentages', function()
  reset(); start()
  assert(dem.health, 'denizen health module missing')
  local function requests()
    local n=0; for _,s in ipairs(gmcpSent) do if s=='IRE.Target.Set "1234"' then n=n+1 end end; return n
  end
  eq(requests(),1); eq(dem.health.get('1234'),nil)
  event('IRE.Target.Info',{id='1234',short_desc='a warrior ant',hpperc='75%'})
  eq(dem.health.get('1234'),75); cycle(); eq(requests(),1)
  messages={}; dem.hunt.status(); assert(table.concat(messages):find('75%',1,true))
end)

test('health validates percentages without changing the attack or retiring IDs', function()
  reset(); start(); local action=dem.balances.action
  for _,sample in ipairs({{'0%',0}, {'100%',100}, {'25.5%',25.5}, {37,37}}) do
    event('IRE.Target.Info',{id='1234',hpperc=sample[1]})
    eq(dem.health.get('1234'),sample[2])
    eq(dem.balances.action,action); assert(not dem.room.retired['1234'])
  end
  for _,v in ipairs({'-1%','101%','oops','nan','1%extra',{},false,math.huge,0/0}) do
    event('IRE.Target.Info',{id='1234',hpperc=v}); eq(dem.health.get('1234'),nil)
  end
  assert(dem.hunt.enabled); assert(dem.room.items['1234'])
end)

test('health ignores unsolicited IDs and same-name successors stay independent', function()
  reset(); setup(); roster({{id='1234',name='a warrior ant',attrib='m'},{id='9',name='a warrior ant',attrib='m'}})
  dem.hunt.toggle(); roster({{id='1234',name='a warrior ant',attrib='m'},{id='9',name='a warrior ant',attrib='m'}}); tick(0)
  event('IRE.Target.Info',{id='9',hpperc='5%'}); eq(dem.health.get('9'),nil)
  event('IRE.Target.Info',{id='1234',hpperc='50%'})
  event('Char.Items.Remove',{location='room',item='1234'}); cycle()
  eq(dem.target,'9'); eq(dem.health.get('1234'),nil); eq(dem.health.get('9'),nil)
  event('IRE.Target.Info',{id='1234',hpperc='0%'}); eq(dem.health.get('9'),nil)
  event('IRE.Target.Info',{id='9',hpperc='80%'}); eq(dem.health.get('9'),80)
end)

test('zero health reconciles once and never authorizes movement or death', function()
  reset(); start(); gmcpSent={}
  event('IRE.Target.Info',{id='1234',hpperc='0%'})
  event('IRE.Target.Info',{id='1234',hpperc='0%'})
  eq(queryCount(),1); assert(dem.room.items['1234']); assert(not dem.room.retired['1234'])
end)

test('generic manual reselection keeps health on the physically pinned duplicate', function()
  reset(); setup()
  local ants={{id='1234',name='a warrior ant',attrib='m'},{id='9',name='a warrior ant',attrib='m'}}
  roster(ants); dem.targeting.setDenizen('9'); dem.hunt.toggle(); roster(ants); tick(0)
  eq(sent[1],'invoke combustion 9'); dem.targeting.setDenizen('ant')
  eq(dem.health.requested,'9')
  event('IRE.Target.Info',{id='1234',hpperc='20%'}); event('IRE.Target.Info',{id='9',hpperc='70%'})
  eq(dem.health.get('9'),70); eq(dem.health.get('1234'),nil)
  cycle(); eq(sent[2],'invoke combustion 9')
end)

test('renaming a physically pinned denizen preserves health ownership', function()
  reset(); setup(); dem.targeting.setDenizen('ant'); dem.hunt.toggle(); roster(); tick(0)
  eq(sent[1],'invoke combustion 1234')
  event('IRE.Target.Info',{id='1234',hpperc='70%'})
  event('Char.Items.Update',{location='room',item={id='1234',name='an injured soldier',attrib='m'}})
  eq(dem.health.requested,'1234')
  event('IRE.Target.Info',{id='1234',hpperc='60%'}); eq(dem.health.get('1234'),60)
  cycle(); eq(sent[2],'invoke combustion 1234')
end)

test('room and connection changes discard health and old target packets', function()
  reset(); start(); event('IRE.Target.Info',{id='1234',hpperc='40%'})
  room('Ant colony',102); event('IRE.Target.Info',{id='1234',hpperc='10%'})
  eq(dem.health.get('1234'),nil)
  roster(); tick(0); event('IRE.Target.Info',{id='1234',hpperc='70%'})
  raiseEvent('sysDisconnectionEvent'); eq(dem.health.get('1234'),nil)
  event('IRE.Target.Info',{id='1234',hpperc='1%'}); eq(dem.health.get('1234'),nil)
end)

-- Map doubles model only external Mudlet APIs. No production pathfinding or
-- movement decisions are replaced. Each destination/command is hand-derived.
local function mapRooms(nodes)
  mmp=nil
  function getRoomArea(n) return nodes[tonumber(n)] and (nodes[tonumber(n)].area or 1) or -1 end
  function getRoomExits(n) return nodes[tonumber(n)] and (nodes[tonumber(n)].exits or {}) or nil end
  function roomLocked(n) return nodes[tonumber(n)] and nodes[tonumber(n)].locked or false end
  function hasExitLock(n,d) return nodes[tonumber(n)].locks and nodes[tonumber(n)].locks[d] or false end
  function getDoors(n) return nodes[tonumber(n)].doors or {} end
end
local function explore(nodes,items)
  reset(); setup(); mapRooms(nodes or {[101]={exits={north=102}},[102]={exits={south=101}}})
  DEMONIC_TEST_EXPLORE_ALIAS(); assert(dem.hunt.enabled); roster(items or {}); tick(0)
end
local function confirmClear() roster({}); tick(0) end
local function directions()
  local result={}; local dirs={n=true,ne=true,e=true,se=true,s=true,sw=true,w=true,nw=true,u=true,d=true,['in']=true,out=true}
  for _,s in ipairs(commands) do if dirs[s] then result[#result+1]=s end end
  return table.concat(result,',')
end

test('exploration confirms clear before sending exactly one movement', function()
  explore(); eq(directions(),''); assert(dem.hunt.enabled)
  confirmClear(); eq(directions(),'n'); assert(dem.navigation.pending)
  dem.onPrompt(); vitals(); tick(1); eq(directions(),'n'); eq(#sent,0)
  room('Ant colony',102); tick(0); eq(directions(),'n'); eq(#sent,0)
  roster({{id='9',name='a warrior ant',attrib='m'}}); tick(0)
  eq(sent[1],'invoke combustion 9'); eq(dem.navigation.pending,nil)
end)

test('exploration fights until final roster reconciliation and real action recovery', function()
  explore(nil,{{id='1234',name='a warrior ant',attrib='m'}}); eq(sent[1],'invoke combustion 1234')
  vitals({eq='0'}); dem.hunt.onKill('a warrior ant'); confirmClear(); eq(directions(),'')
  vitals(); tick(0); confirmClear(); eq(directions(),'n')
end)

test('new listed arrivals invalidate clear confirmation and get attacked', function()
  explore(); event('Char.Items.Add',{location='room',item={id='9',name='a warrior ant',attrib='m'}})
  roster({{id='9',name='a warrior ant',attrib='m'}}); tick(0)
  eq(directions(),''); eq(sent[1],'invoke combustion 9')
end)

test('exploration ignores unlisted protected and dead entries for departure', function()
  local ignored={{id='1',name='Fido',attrib='m'},{id='2',name='a warrior ant',attrib='mx'},{id='3',name='a warrior ant',attrib='md'}}
  explore(nil,ignored); roster(ignored); tick(0); eq(directions(),'n'); eq(#sent,0)
end)

test('BFS chooses nearest rooms and numeric destination ties', function()
  explore({[101]={exits={north=103,east=102}},[102]={},[103]={}})
  confirmClear(); eq(directions(),'e'); eq(dem.navigation.destination,'102')
end)

test('BFS backtracks through checked rooms and stops after a branching pass', function()
  explore({[101]={exits={north=102,east=103}},[102]={exits={south=101}},[103]={exits={west=101}}})
  confirmClear(); eq(directions(),'n'); room('Ant colony',102); confirmClear(); confirmClear()
  eq(directions(),'n,s'); room('Ant colony',101); confirmClear(); confirmClear()
  eq(directions(),'n,s,e'); room('Ant colony',103); confirmClear(); confirmClear()
  assert(not dem.hunt.enabled); eq(directions(),'n,s,e'); eq(dem.navigation.pending,nil)
  assert(table.concat(messages):lower():find('complete',1,true))
end)

test('cycles terminate without endlessly revisiting rooms', function()
  explore({[101]={exits={east=102}},[102]={exits={south=103}},[103]={exits={west=101}}})
  confirmClear(); room('Ant colony',102); confirmClear(); confirmClear()
  room('Ant colony',103); confirmClear(); confirmClear()
  eq(directions(),'e,s'); assert(not dem.hunt.enabled)
end)

test('exploration excludes locked closed unmapped and other-area destinations', function()
  explore({[101]={exits={north=102,east=103,south=104,west=105,up=999,down=106},locks={east=true},doors={south=2}},
    [102]={locked=true},[103]={},[104]={},[105]={area=2},[106]={}})
  confirmClear(); eq(directions(),'d')
end)

test('exploration rejects missing map APIs and empty hunt lists without enabling', function()
  reset(); setup(); getRoomArea=nil; assert(not dem.hunt.toggle('explore')); assert(not dem.hunt.enabled)
  mapRooms({}); assert(not dem.hunt.toggle('explore')); assert(not dem.hunt.enabled)
  mapRooms({[101]={}}); dem.hunt.remove('a warrior ant')
  assert(not dem.hunt.toggle('explore')); assert(not dem.hunt.enabled)
end)

test('movement barrier blocks emergency shielding until arrival roster', function()
  explore(); confirmClear(); vitals({hp='40',maxhp='100'}); dem.onPrompt(); eq(#sent,0)
  room('Ant colony',102); dem.onPrompt(); eq(#sent,0)
  roster({}); dem.onPrompt(); eq(sent[1],'unleash arctar at me')
end)

test('exploration waits for standing unstunned readiness and shields before leaving', function()
  explore(); vitals({prone='1'}); confirmClear(); eq(directions(),'')
  vitals({prone='0',stunned='1'}); tick(0); eq(directions(),'')
  vitals({stunned='0',bal='0'}); tick(0); eq(directions(),'')
  vitals({hp='40',maxhp='100'}); tick(0); eq(sent[1],'unleash arctar at me'); eq(directions(),'')
end)

test('movement timeout never retries a direction and stops Hunt', function()
  explore(); confirmClear(); tick(10); eq(directions(),'n'); assert(not dem.hunt.enabled)
  tick(20); eq(directions(),'n'); eq(dem.navigation.pending,nil)
end)

test('wrong direction packet stops a pending automatic movement', function()
  explore(); confirmClear(); event('Room.WrongDir','n'); tick(0)
  assert(not dem.hunt.enabled); eq(directions(),'n')
end)

test('unexpected arrivals and area changes stop before attacking', function()
  for _,arrival in ipairs({{id=900,area='Ant colony'},{id=102,area='Elsewhere'}}) do
    explore(); confirmClear(); room(arrival.area,arrival.id); roster(); tick(0)
    assert(not dem.hunt.enabled); eq(#sent,0); eq(directions(),'n')
  end
end)

test('manual denizen targeting ends exploration and preserves stationary combat', function()
  explore(nil,{{id='2335',name='Fido',attrib='m'}}); dem.targeting.setDenizen('2335'); tick(0)
  assert(not dem.navigation.active); assert(dem.hunt.enabled); eq(sent[1],'invoke combustion 2335'); eq(directions(),'')
end)

test('manual targeting during transit cannot bypass the movement barrier', function()
  explore(); confirmClear(); dem.targeting.setDenizen('1234'); roster(); tick(0)
  eq(#sent,0); eq(directions(),'n'); assert(not dem.hunt.enabled)
end)

test('stop death connection and reload cancel navigation callbacks', function()
  for _,cancel in ipairs({function() dem.hunt.toggle() end,function() vitals({hp='0'}) end,
      function() raiseEvent('sysDisconnectionEvent') end,function() DEMONIC_TEST_LOAD() end}) do
    explore(); confirmClear(); cancel(); tick(20)
    assert(not dem.hunt.enabled); assert(not dem.navigation.active); eq(dem.navigation.pending,nil); eq(directions(),'n')
  end
end)

test('clear roster timeout stops exploration without a movement', function()
  explore(); tick(10); assert(not dem.hunt.enabled); eq(directions(),'')
end)

test('mapper speedwalking cannot run concurrently with exploration', function()
  explore(); mmp={autowalking=true}; confirmClear(); assert(not dem.hunt.enabled); eq(directions(),'')
end)

test('path ties use alphabetic direction commands rather than intermediate ID order', function()
  explore({[101]={exits={north=102,east=103}},[102]={exits={east=104}},[103]={exits={north=104}},[104]={}})
  -- Both intermediate rooms were already checked; 104 has two equally short paths.
  dem.navigation.visited['102']=true; dem.navigation.visited['103']=true
  confirmClear(); eq(directions(),'e'); eq(dem.navigation.destination,'104')
end)

test('arrival without a full roster times out and no stale roster attacks', function()
  explore(); confirmClear(); room('Ant colony',102)
  event('Char.Items.Add',{location='room',item={id='9',name='a warrior ant',attrib='m'}}); tick(0)
  eq(#sent,0); tick(10); assert(not dem.hunt.enabled); eq(#sent,0); eq(directions(),'n')
end)

test('an unsolicited full list for the old room cannot release the movement barrier', function()
  explore(); confirmClear(); roster(); dem.onPrompt(); eq(#sent,0); assert(dem.navigation.pending)
  room('Ant colony',102); tick(0); eq(#sent,0)
  roster({{id='9',name='a warrior ant',attrib='m'}}); tick(0); eq(sent[1],'invoke combustion 9')
end)

test('explicit player selection and clear stop exploration without a movement', function()
  for _,select in ipairs({function() dem.targeting.setPlayer('Aeden') end,function() dem.targeting.clear() end}) do
    explore(); select(); tick(20); assert(not dem.hunt.enabled); assert(not dem.navigation.active); eq(directions(),'')
  end
end)

test('resource stops and active combat prevent exploration from departing', function()
  explore(); vitals({mp='1',maxmp='100'}); confirmClear(); assert(not dem.hunt.enabled); eq(directions(),'')
  explore(); dem.settings.hpLimit=60; vitals({hp='50',maxhp='100'}); confirmClear()
  assert(not dem.hunt.enabled); eq(directions(),'')
end)

test('restarting a completed pass visits the area again without restored session state', function()
  explore({[101]={}}); confirmClear(); assert(not dem.hunt.enabled)
  mapRooms({[101]={exits={north=102}},[102]={}}); DEMONIC_TEST_EXPLORE_ALIAS(); confirmClear(); confirmClear()
  eq(directions(),'n'); assert(dem.navigation.active)
end)

test('listed respawns in a backtracking room are fought before taking the next step', function()
  explore({[101]={exits={north=102,east=103}},[102]={exits={south=101}},[103]={}})
  confirmClear(); room('Ant colony',102); confirmClear(); confirmClear(); eq(directions(),'n,s')
  room('Ant colony',101); roster({{id='9',name='a warrior ant',attrib='m'}}); tick(0)
  eq(sent[1],'invoke combustion 9'); eq(directions(),'n,s')
end)

test('removing the final allowlist entry stops exploration instead of clearing the area', function()
  explore(); dem.hunt.remove('a warrior ant'); confirmClear()
  assert(not dem.hunt.enabled); eq(directions(),'')
end)

for _, t in ipairs(tests) do
  local ok, err = pcall(t[2])
  if ok then passed=passed+1; print('PASS '..t[1])
  else failed=failed+1; print('FAIL '..t[1]..': '..tostring(err)) end
end
print(string.format('%d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
