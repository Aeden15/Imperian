-- Exercises actual embedded package code with only external Mudlet widgets/I/O doubled.
local tests, passed, failed = {}, 0, 0
local function test(name, fn) tests[#tests + 1] = {name, fn} end
local function eq(a,b) assert(a == b, 'expected '..tostring(b)..', got '..tostring(a)) end
local widgets, layouts, handlers, timers, sent, queries, messages
local Widget = {}
function Widget:new(cons, parent)
  local w = setmetatable({cons=cons, name=cons.name, text='', entries={}, children={}, hidden=false}, {__index=self})
  assert(not widgets[w.name], 'duplicate widget '..w.name)
  widgets[w.name] = w
  if parent then parent.children[#parent.children+1] = w end
  if cons.autoLoad ~= false and layouts[w.name] then
    for k,v in pairs(layouts[w.name]) do w.cons[k]=v end
    w.hidden = w.cons.hidden or false
  end
  return w
end
function Widget:setStyleSheet(s) self.style=s end
function Widget:setTitle(s) self.title=s end
function Widget:clear() self.text=''; self.entries={} end
function Widget:echo(s) self.text=self.text..s end
function Widget:cecho(s) error('server text must not be interpreted as cecho markup') end
function Widget:echoPopup(s, actions, hints) self:echo(s); self.entries[#self.entries+1]={text=s,actions=actions,hints=hints,color=self.fg} end
function Widget:echoLink(s, action, hint) self:echoPopup(s,{action},{hint}) end
function Widget:setColor(r,g,b) self.fg={r,g,b} end
function Widget:setFgColor(r,g,b) self.fg={r,g,b} end
function Widget:show() self.hidden=false end
function Widget:hide() self.hidden=true end
function Widget:move(x,y) self.cons.x=x; self.cons.y=y end
function Widget:resize(w,h) self.cons.width=w; self.cons.height=h end
function Widget:save()
  layouts[self.name]={x=self.cons.x,y=self.cons.y,width=self.cons.width,height=self.cons.height,hidden=self.hidden}
end
function Widget:delete()
  for _,child in ipairs(self.children) do child:delete() end
  widgets[self.name]=nil; self.deleted=true
end
function Widget:disableAutoSave() end
function Widget:restore() self.minimized=false end
function Widget:unlockContainer() self.locked=false end
function Widget:detach() end
function Widget:disconnect() end

local function reset(options)
  options=options or {}
  dem=nil; gmcp={}; widgets={}; layouts=options.layouts or {}; handlers={}; timers={}; sent={}; queries={}; messages={}
  if options.headless then Geyser=nil; Adjustable=nil
  else Geyser={Label=Widget, MiniConsole=Widget}; Adjustable={Container=Widget} end
  function echo(s) messages[#messages+1]=s end
  function cecho(s) messages[#messages+1]=s end
  function send(s) sent[#sent+1]=s end
  function sendGMCP(s) queries[#queries+1]=s end
  function getMudletHomeDir() return '/test-profile' end
  function getEpoch() return 0 end
  function tempTimer(seconds,fn) timers[#timers+1]={fn=fn,seconds=seconds,active=true}; return #timers end
  function killTimer(id) if timers[id] then timers[id].active=false end end
  function registerAnonymousEventHandler(event,fn) handlers[#handlers+1]={event=event,fn=fn,active=true}; return #handlers end
  function killAnonymousEventHandler(id) if handlers[id] then handlers[id].active=false end end
  function raiseEvent(event,...)
    local copy={}; for _,h in ipairs(handlers) do copy[#copy+1]=h end
    for _,h in ipairs(copy) do if h.active and h.event==event then h.fn(event,...) end end
  end
  table.load=function() error('no settings') end
  table.save=function() end
  DEMONIC_TEST_LOAD()
  assert(dem.ui, 'room GUI is not bundled')
end
local function flush()
  for _=1,10 do
    local found=false
    for _,t in ipairs(timers) do if t.active and t.seconds==0 then t.active=false; t.fn(); found=true end end
    if not found then return end
  end
  error('GUI timers do not settle')
end
local function event(name,payload)
  local node=gmcp; local parts={}; for part in name:gmatch('[^.]+') do parts[#parts+1]=part end
  for i=1,#parts-1 do node[parts[i]]=node[parts[i]] or {}; node=node[parts[i]] end
  node[parts[#parts]]=payload; raiseEvent('gmcp.'..name)
end
local function room(num) event('Room.Info',{num=num or 101,name='A <red> room',area='Ant colony'}) end
local function roster(items) event('Char.Items.List',{location='room',items=items or {
  {id='11',name='an ant',attrib='m'}, {id='12',name='an ant',attrib='m'},
  {id='13',name='a guardian',attrib='mx'}, {id='14',name='a corpse',attrib='md'},
  {id='15',name='a <red> gem',attrib='t'}}}) end
local function panel(kind) return assert(dem.ui.panels[kind]) end
local function body(kind) return panel(kind).console end
local function entry(kind,pattern)
  for _,v in ipairs(body(kind).entries) do if v.text:find(pattern,1,true) then return v end end
  error('missing entry '..pattern)
end
local function action(row,hint)
  for i,s in ipairs(row.hints) do if s:find(hint,1,true) then return row.actions[i]() end end
  error('missing action '..hint)
end
local function queryCount()
  local n=0; for _,s in ipairs(queries) do if s=='Char.Items.Room ""' then n=n+1 end end; return n
end

test('three panels initialize once with dark styles and no polling', function()
  reset(); local p=panel('denizens'); assert(p.container.cons.adjLabelstyle:find('#',1,true));
  dem.ui.init(); eq(panel('denizens'),p); eq(queryCount(),0); eq(#sent,0)
  room(); flush(); eq(queryCount(),1); assert(not dem.hunt.enabled); assert(body('items').text:find('Waiting',1,true))
  event('Room.Info',{num=101,name='Same room'}); flush(); eq(queryCount(),1)
end)
test('grouped denizens and exact ID menus share targeting and allowlists', function()
  reset(); room(); roster(); flush(); local row=entry('denizens','an ant x2')
  action(row,'Target ID 12'); eq(dem.target,'12'); eq(dem.targeting.kind,'denizen'); assert(not dem.hunt.enabled); eq(#sent,0)
  action(row,'Add name'); assert(dem.settings.areas['Ant colony']['an ant']); flush()
  assert(body('denizens').text:find('[T]',1,true)); assert(body('denizens').text:find('a guardian [protected]',1,true))
  local rgb=entry('denizens','an ant').color; eq(rgb[1],dem.ui.palette.selected[1])
  dem.targeting.clear(); flush(); rgb=entry('denizens','an ant').color; eq(rgb[1],dem.ui.palette.allowed[1])
  assert(not dem.ui.lastError)
end)

test('selected duplicate groups show only the selected ID health and update without combat', function()
  reset(); room(); roster(); flush(); action(entry('denizens','an ant'),'Target ID 12'); flush()
  assert(body('denizens').text:find('[ID 12: unknown]',1,true))
  event('IRE.Target.Info',{id='11',hpperc='10%'}); flush()
  assert(not body('denizens').text:find('10%',1,true))
  event('IRE.Target.Info',{id='12',hpperc='75%'}); flush()
  assert(body('denizens').text:find('an ant x2 [ID 12: 75%]',1,true)); eq(#sent,0); assert(not dem.hunt.enabled)
  event('IRE.Target.Info',{id='12',hpperc='invalid'}); flush()
  assert(body('denizens').text:find('[ID 12: unknown]',1,true))
  dem.targeting.clear(); flush(); assert(not body('denizens').text:find('[ID',1,true))
end)

test('generic manual targeting during combat displays the pinned duplicate ID', function()
  reset(); room(); roster()
  event('Char.Vitals',{bal='1',eq='1',hp='1000',maxhp='1000',mp='1000',maxmp='1000',prone='0',stunned='0'})
  dem.hunt.add('ant'); dem.targeting.setDenizen('12'); dem.hunt.toggle(); roster(); flush()
  eq(sent[1],'invoke combustion 12'); dem.targeting.setDenizen('ant')
  event('IRE.Target.Info',{id='12',hpperc='70%'}); flush()
  assert(body('denizens').text:find('[ID 12: 70%]',1,true))
  event('Char.Items.Update',{location='room',item={id='12',name='an injured soldier',attrib='m'}})
  event('IRE.Target.Info',{id='12',hpperc='60%'}); flush()
  assert(body('denizens').text:find('[T] an injured soldier [ID 12: 60%]',1,true))
end)
test('items retain IDs, literal names and get/probe actions', function()
  reset(); room(); roster(); flush(); assert(body('items').text:find('a corpse',1,true));
  local row=entry('items','a <red> gem'); action(row,'Get'); action(row,'Probe')
  eq(sent[1],'get 15'); eq(sent[2],'probe 15'); assert(not body('denizens').text:find('a corpse',1,true))
end)
test('players replace add remove exclude self and explicitly select a player', function()
  reset(); room(); event('Char.Name',{name='Aeden'});
  event('Room.Players',{{name='Aeden',fullname='Self'},{name='Friend',fullname='Friend the Brave'}}); flush()
  assert(not body('players').text:find('Aeden',1,true)); action(entry('players','Friend'),'Target'); eq(dem.targeting.kind,'player')
  event('Room.AddPlayer',{name='Visitor',fullname='A Visitor'}); flush(); assert(dem.room.players.visitor)
  event('Room.RemovePlayer','FRIEND'); flush(); assert(not dem.room.players.friend)
  event('Room.Players',{Other='Other the Great'}); flush(); assert(dem.room.players.other); assert(not dem.room.players.visitor)
end)
test('room transitions clear immediately and reject old popup actions', function()
  reset(); room(); roster(); event('Room.Players',{{name='Friend'}}); flush()
  local mob=entry('denizens','an ant'); local item=entry('items','gem'); local player=entry('players','Friend')
  room(102); assert(not body('denizens').text:find('an ant',1,true)); assert(not body('players').text:find('Friend',1,true))
  action(mob,'Target ID 11'); action(mob,'Add name'); action(item,'Get'); action(player,'Target')
  eq(dem.target,nil); eq(#sent,0); eq(dem.settings.areas['Ant colony'],nil); assert(not dem.room.playersReady)
end)
test('membership and protection are rechecked when popup executes', function()
  reset(); room(); roster(); flush(); local mob=entry('denizens','an ant'); local item=entry('items','gem')
  event('Char.Items.Update',{location='room',item={id='11',attrib='mx'}}); action(mob,'Target ID 11'); eq(dem.target,nil)
  event('Char.Items.Remove',{location='room',item='15'}); action(item,'Get'); eq(#sent,0)
end)
test('empty and disconnected differ and preidentity players are ignored', function()
  reset(); event('Room.Players',{{name='Ghost'}}); assert(not dem.room.playersReady)
  room(); roster({}); event('Room.Players',{}); flush(); assert(body('denizens').text:find('None',1,true))
  raiseEvent('sysDisconnectionEvent'); assert(body('players').text:find('Disconnected',1,true)); eq(dem.room.name,nil)
end)
test('delta packets update groups and retirement removes only live entries', function()
  reset(); room(); roster(); flush();
  event('Char.Items.Remove',{location='room',item='11'}); flush(); assert(not body('denizens').text:find('x2',1,true))
  event('Char.Items.Add',{location='inv',item={id='50',name='inventory',attrib='t'}}); flush(); assert(not body('items').text:find('inventory',1,true))
  dem.room.retired['12']=true; dem.room.notify(); flush(); assert(not body('denizens').text:find('an ant',1,true))
  event('Char.Items.Update',{location='room',item={id='12',name='a dead ant',attrib='md'}}); flush(); assert(body('items').text:find('a dead ant',1,true))
end)
test('layout visibility persistence reset and reload clean up owned widgets', function()
  reset(); local c=panel('items').container; c:move(400,200); c:resize(500,240); dem.ui.hide();
  local old=dem; old.shutdown(); eq(next(widgets),nil); assert(layouts[c.name].hidden)
  local savedLayouts=layouts; reset({layouts=savedLayouts}); c=panel('items').container; eq(c.cons.x,400); eq(c.cons.width,500); assert(c.hidden)
  dem.ui.show(); assert(not c.hidden); dem.ui.resetLayout(); eq(c.cons.width,300); eq(c.cons.x,0)
  local before=dem; DEMONIC_TEST_LOAD(); assert(dem~=before); assert(before.ui.panels.items==nil); assert(panel('items'))
end)
test('headless init retries on load and GUI failures cannot interrupt hunt state', function()
  reset({headless=true}); room(); roster(); eq(queryCount(),0)
  Geyser={Label=Widget,MiniConsole=Widget}; Adjustable={Container=Widget}; raiseEvent('sysLoadEvent'); assert(panel('items'))
  body('items').clear=function() error('widget failure') end
  event('Char.Vitals',{bal='1',eq='1',hp='1000',maxhp='1000',mp='1000',maxmp='1000',prone='0',stunned='0',health='1'})
  dem.hunt.add('ant'); dem.hunt.toggle(); roster(); flush()
  assert(dem.room.ready); assert(dem.room.items['11']); assert(dem.hunt.enabled); eq(sent[1],'invoke combustion 11')
  assert(dem.ui.lastError:find('widget failure',1,true))
  panel('items').container.save=function() error('disk failure') end; dem.shutdown(); eq(next(widgets),nil)
end)
test('hidden GUI does not request rosters until shown', function()
  reset(); dem.ui.hide(); room(); eq(queryCount(),0); dem.ui.show(); eq(queryCount(),1); dem.ui.show(); eq(queryCount(),1)
end)
test('callbacks from a reloaded package cannot act on the new runtime', function()
  reset(); room(); roster(); flush(); local row=entry('items','gem'); local mob=entry('denizens','an ant')
  DEMONIC_TEST_LOAD(); room(); roster(); flush(); action(row,'Get'); action(mob,'Target ID 11')
  eq(#sent,0); eq(dem.target,nil)
end)
test('GUI aliases execute the bundled show hide and reset scripts', function()
  reset(); DEMONIC_TEST_GUI_ALIAS('hide'); assert(panel('items').container.hidden)
  DEMONIC_TEST_GUI_ALIAS('show'); assert(not panel('items').container.hidden)
  panel('items').container:move(500,400); DEMONIC_TEST_GUI_ALIAS('reset'); eq(panel('items').container.cons.x,0)
end)
test('failed widget constructors roll back and permit a later init retry', function()
  reset({headless=true}); Geyser={Label=Widget,MiniConsole={new=function() return nil,'native window unavailable' end}}
  Adjustable={Container=Widget}; eq(dem.ui.init(),false); assert(not dem.ui.initialized); eq(next(widgets),nil)
  Geyser.MiniConsole=Widget; assert(dem.ui.init()); assert(panel('items').console); assert(dem.ui.initialized)
end)

for _,t in ipairs(tests) do
  local ok,err=pcall(t[2]); if ok then passed=passed+1; print('PASS GUI '..t[1])
  else failed=failed+1; print('FAIL GUI '..t[1]..': '..tostring(err)) end
end
print(string.format('GUI: %d passed, %d failed',passed,failed)); if failed>0 then os.exit(1) end
