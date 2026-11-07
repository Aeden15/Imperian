-- Room packets are an ordered stream. Native item lists carry no room or
-- request ID, so arbitrary delayed replies cannot be assigned to a room.
-- Generations guard local callbacks and targets; Room.Info confirms identity.
dem.room = {items = {}, order = {}, retired = {}, ready = false,
  phase = 'unconfirmed', generation = 0, contextId = 0}
local room = dem.room
local pendingMoves, lastIdentity = 0, nil
local movementOnlyPacket = false
local submissionSequence, ambiguousSubmission = 0, nil
local nextContext, exitsByRoom, movementOrigin = 0, {}, nil
local lastReceivedRoom, rejectedReason
-- Text and Room.Info acknowledge the same arrival in either order. Only
-- Room.Info consumes queued movement or supplies an identity.
local arrivals, currentArrival, awaitingArrival = {}, nil, false
-- A native heading is useful only in the output frame opened by successful
-- walk text. Keep fresh packets separately from accepted identity so a stale
-- exit prediction cannot discard the packet needed to corroborate that frame.
local headingFrame, freshInfo, recoveryReason
local timerKeys = {'room-initial', 'room-retry', 'room-fallback', 'room-timeout'}

local function id(value)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  local s = tostring(value)
  if not s:match('^%d+$') then return nil end
  s = s:gsub('^0+', '')
  if s == '' then return nil end
  return s
end

local function record(value, previous)
  if type(value) ~= 'table' then return nil end
  local key = id(value.id)
  if not key then return nil end
  local result = {}
  for k, v in pairs(previous or {}) do result[k] = v end
  for k, v in pairs(value) do result[k] = v end
  result.id = key
  return result, key
end

local function roomName(value)
  if type(value) ~= 'string' then return nil end
  local name = dem.norm(value):gsub('%.$', '')
  name = dem.trim(name)
  return name ~= '' and name or nil
end

local function changed()
  if dem.schedule then dem.schedule() end
end

function room.living(item)
  if type(item) ~= 'table' or not id(item.id) or type(item.name) ~= 'string'
      or dem.trim(item.name) == '' then return false end
  local attr = type(item.attrib) == 'string' and item.attrib:lower() or ''
  return attr:find('m', 1, true) ~= nil and not attr:find('d', 1, true)
end

function room.eligible(item)
  return room.living(item) and not item.attrib:lower():find('x', 1, true)
end

local function nameWords(name)
  return name:lower():gmatch('[%w_%-]+')
end

local function keyword(word)
  return word ~= 'a' and word ~= 'an' and word ~= 'the'
end

function room.matchesReference(item, reference)
  if type(item) ~= 'table' or type(item.name) ~= 'string' then return false end
  local key, valid = id(item.id), dem.validReference(reference)
  if not key or not valid then return false end
  local ref = valid:lower()
  if ref == key then return true end
  for word in nameWords(item.name) do
    if keyword(word) and (ref == word or ref == word .. key) then return true end
  end
  return false
end

function room.matchesAllowlist(item, allowed)
  if type(item) ~= 'table' or type(item.name) ~= 'string' or type(allowed) ~= 'table' then return false end
  local name = dem.norm(item.name)
  for entry, enabled in pairs(allowed) do
    if enabled == true and type(entry) == 'string' then
      local normalized = dem.norm(entry)
      if normalized ~= '' then
        if normalized == name then return true end
        if normalized:match('^[%w_%-]+$') and keyword(normalized) then
          for word in nameWords(item.name) do
            if word == normalized then return true end
          end
        end
      end
    end
  end
  return false
end

function room.cancelRefresh()
  for _, key in ipairs(timerKeys) do dem.cancel(key) end
  room.refresh = nil
end

local function invalidate()
  room.cancelRefresh()
  room.generation = room.generation + 1
  room.num, room.area = nil, nil
  room.items, room.order, room.retired = {}, {}, {}
  room.ready, room.phase = false, 'unconfirmed'
end

function room.reset()
  invalidate()
  pendingMoves, lastIdentity = 0, nil
  movementOnlyPacket = false
  submissionSequence, ambiguousSubmission = 0, nil
  arrivals, currentArrival, awaitingArrival = {}, nil, false
  nextContext, room.contextId, exitsByRoom, movementOrigin = 0, 0, {}, nil
  lastReceivedRoom, rejectedReason = nil, nil
  headingFrame, freshInfo, recoveryReason = nil, nil, nil
  room.subscribed, room.processingList = false, false
end

function room.subscribe()
  if room.subscribed then return end
  room.subscribed = true
  if type(sendGMCP) == 'function' then
    sendGMCP('Core.Supports.Add ["Char 1","Char.Items 1","Room 1"]')
  end
end

local function hunting()
  return dem.hunt and dem.hunt.enabled == true
end

local function request(reason, deferInitial)
  local active = hunting()
  local previous = room.refresh
  -- An install-time query has no recovery budget. Enabling hunting upgrades
  -- it to a fresh active cycle; repeated active requests share one budget.
  if previous and previous.id == room.generation and previous.active == active then return true end
  room.cancelRefresh()
  room.ready, room.phase = false, room.num and 'waiting' or 'unconfirmed'
  local refresh = {id = room.generation, started = dem.now(), attempts = 0,
    ihSent = false, reason = reason or 'Room refresh', active = active}
  room.refresh = refresh
  local function current()
    return room.refresh == refresh and room.generation == refresh.id
      and refresh.active and hunting()
  end
  local function query()
    refresh.attempts = refresh.attempts + 1
    if type(sendGMCP) == 'function' then sendGMCP('Char.Items.Room ""') end
  end
  if deferInitial and active then
    dem.defer('room-initial', 0, function() if current() then query() end end)
  else
    query()
  end
  if active then
    dem.defer('room-retry', 1, function() if current() then query() end end)
    -- Outgoing movement invalidates targets immediately, but its recovery
    -- grace starts at arrival rather than before a slow command executes.
    if not awaitingArrival then
      dem.defer('room-fallback', 0.2, function()
        if not current() then return end
        refresh.ihSent = true
        if type(send) == 'function' then send('ih') end
      end)
    end
    dem.defer('room-timeout', 10, function()
      if not current() then return end
      local reason = room.num and 'The full room roster did not arrive.'
        or 'The room identity was not confirmed by Room.Info.'
      dem.hunt.stop(reason)
    end)
  end
  return true
end

function room.request(reason) return request(reason, false) end

local directions = {n=true, ne=true, e=true, se=true, s=true, sw=true, w=true,
  nw=true, u=true, d=true, ['in']=true, out=true, north=true, northeast=true,
  east=true, southeast=true, south=true, southwest=true, west=true,
  northwest=true, up=true, down=true}
local fullDirection = {n='north', ne='northeast', e='east', se='southeast',
  s='south', sw='southwest', w='west', nw='northwest', u='up', d='down'}

local function direction(value)
  if type(value) ~= 'string' then return nil end
  value = dem.trim(value):lower()
  if not directions[value] then return nil end
  return fullDirection[value] or value
end

local function newContext()
  nextContext = nextContext + 1
  room.contextId = nextContext
  return nextContext
end

-- These are predictions only. Neither a cached exit nor an item list can
-- acknowledge movement; a newly received Room.Info must still match it.
local function expectedPath()
  local source = movementOrigin
  for _, arrival in ipairs(arrivals) do
    local exits = source and exitsByRoom[source]
    arrival.expected = exits and exits[arrival.direction] or nil
    source = arrival.identity and arrival.identity.num or arrival.expected
  end
end

local function acknowledgeSubmission(arrival)
  -- In the ordered command stream, a proven later movement also accounts
  -- for earlier command responses. An older walk cannot clear newer ambiguity.
  if ambiguousSubmission and arrival.submissionSequence
      and arrival.submissionSequence >= ambiguousSubmission then
    ambiguousSubmission = nil
  end
end

function room.diagnostics()
  expectedPath()
  local latest = arrivals[#arrivals]
  local blocking
  for _, arrival in ipairs(arrivals) do
    if not arrival.info then blocking = arrival; break end
  end
  return {contextId = room.contextId, pendingMoves = pendingMoves,
    expectedDestination = latest and latest.expected,
    lastReceivedRoom = lastReceivedRoom, rejectedReason = rejectedReason,
    blockingContext = blocking and blocking.contextId,
    blockingDirection = blocking and blocking.direction,
    blockingExpected = blocking and blocking.expected,
    recoveryReason = recoveryReason}
end

function room.onMovement(command)
  movementOnlyPacket = false
  if type(command) ~= 'string' then return end
  local moves, first, movementOnly = {}, 1, true
  local separator = dem.separator
  while true do
    local boundary = command:find(separator, first, true)
    local part = command:sub(first, boundary and boundary - 1 or #command)
    part = dem.trim(part):lower()
    submissionSequence = submissionSequence + 1
    local heading = direction(part)
    if heading then
      moves[#moves + 1] = {direction = heading, textEligible = true,
        hinted = true, contextId = newContext(), submissionSequence = submissionSequence}
    else
      movementOnly = false
      local action = dem.balances and dem.balances.action
      local trackedAttack = action and action.command == part
      -- These observation commands cannot produce a balance refusal. Other
      -- commands remain ambiguous across later submissions until proven past.
      if part ~= 'look' and part ~= 'l' and part ~= 'ih' and not trackedAttack then
        ambiguousSubmission = submissionSequence
      end
    end
    if not boundary then break end
    first = boundary + #separator
  end
  movementOnlyPacket = movementOnly and #moves > 0
  if #moves == 0 then return end
  headingFrame, freshInfo, recoveryReason = nil, nil, nil
  local unresolved
  for _, arrival in ipairs(arrivals) do
    if not arrival.info then unresolved = true; break end
  end
  if pendingMoves == 0 and not unresolved then
    if room.num then lastIdentity = {num = room.num, area = room.area} end
    movementOrigin = lastIdentity and lastIdentity.num
    arrivals = {}
  end
  for _, arrival in ipairs(moves) do arrivals[#arrivals + 1] = arrival end
  pendingMoves = pendingMoves + #moves
  expectedPath()
  rejectedReason = nil
  invalidate()
  currentArrival, awaitingArrival = nil, true
  if dem.hunt then dem.hunt.onRoomChanged() end
  -- sysDataSendRequest runs before the original command is transmitted.
  if hunting() then request('Movement awaiting Room.Info', true) end
  changed()
end

local function area(value)
  return type(value) == 'string' and dem.trim(value) ~= '' and value or nil
end

local function confirmed(identity, arrival)
  local fresh = not arrival.generation
  -- A delayed acknowledgement of an intermediate arrival must not replace
  -- the cycle already started by text for a later queued movement.
  if not fresh and arrival.generation ~= room.generation then return end
  if fresh then
    invalidate()
    arrival.generation = room.generation
    currentArrival, awaitingArrival = arrival, false
  end
  if identity then room.num, room.area = identity.num, identity.area end
  if not room.ready then room.phase = room.num and 'waiting' or 'unconfirmed' end
  if fresh and dem.hunt then dem.hunt.onRoomChanged() end
  local pendingTarget = dem.targeting and dem.targeting.kind == 'pending'
  if (hunting() or pendingTarget) and not room.ready then
    room.request(identity and 'Room identity confirmed' or 'Room entry confirmed')
  end
  changed()
end

local function headingConflicts(arrival, identity)
  local frame = headingFrame
  return frame and not frame.closed and frame.headingSeen and frame.arrival == arrival
    and arrival.generation == room.generation and frame.name and frame.num
    and (frame.name ~= identity.name or frame.num ~= identity.num)
end

local function blockHeadingConflict(arrival)
  -- A normal fast-path identity can be contradicted by its following native
  -- heading. Roll back that acknowledgement, never the submitted attack.
  if arrival.info then
    arrival.info = false
    if arrival.hinted then pendingMoves = pendingMoves + 1 end
  end
  arrival.identity = nil
  room.num, room.area, room.ready, room.phase = nil, nil, false, 'unconfirmed'
  room.items, room.order, room.retired = {}, {}, {}
  rejectedReason = 'Native heading conflicts with Room.Info.'
  recoveryReason = 'Waiting for Room.Info matching the captured native heading.'
  if hunting() or (dem.targeting and dem.targeting.kind == 'pending') then
    room.request('Native heading and Room.Info disagree')
  end
  changed()
end

local function recoverHeading()
  local frame, packet = headingFrame, freshInfo
  if not frame or frame.closed or not frame.headingSeen then return false end
  local arrival = frame.arrival
  -- The regular Info-first path may already own a fresh roster. Its following
  -- heading must not retire that roster or spend another recovery budget.
  if arrival.info then return false end
  if arrival.generation ~= room.generation then return false end
  if not packet or not frame.name or not frame.num
      or frame.name ~= packet.name or frame.num ~= packet.identity.num then
    recoveryReason = 'Waiting for matching fresh Room.Info and native heading.'
    return false
  end
  local frameIndex
  for i, candidate in ipairs(arrivals) do
    if candidate == arrival then frameIndex = i; break end
    if not candidate.info and not candidate.entered then
      recoveryReason = 'An older movement has no successful entry or Room.Info.'
      return false
    end
  end
  if not frameIndex then return false end
  -- Proof accounts only for the prefix through this frame. A later queued
  -- command retains the identity barrier even if this destination is known.
  for i = 1, frameIndex do
    local candidate = arrivals[i]
    if not candidate.info then
      candidate.info = true
      if candidate.hinted then pendingMoves = pendingMoves - 1 end
    end
    acknowledgeSubmission(candidate)
  end
  local later
  for i = frameIndex + 1, #arrivals do
    if not arrivals[i].info then later = true; break end
  end
  local identity = packet.identity
  arrival.identity, lastIdentity = identity, identity
  frame.closed = true
  rejectedReason, recoveryReason = nil, 'Native heading and fresh Room.Info confirmed the arrival.'
  room.items, room.order, room.retired = {}, {}, {}
  room.num, room.area, room.ready = nil, nil, false
  local previous = room.refresh
  confirmed(not later and pendingMoves == 0 and identity or nil, arrival)
  -- Keep the arrival's existing retry, IH and timeout deadlines. One query is
  -- needed after proof because lists received before identity were discarded.
  local refresh = room.refresh
  if refresh and refresh == previous and refresh.id == room.generation then
    refresh.attempts = refresh.attempts + 1
    if type(sendGMCP) == 'function' then sendGMCP('Char.Items.Room ""') end
  elseif not refresh then
    room.request('Native heading recovery')
  end
  return true
end

function room.onEntered(value)
  local heading = direction(value)
  if not heading then return end
  local arrival
  for _, candidate in ipairs(arrivals) do
    if candidate.textEligible and not candidate.entered then
      if not candidate.direction or candidate.direction == heading then arrival = candidate end
      break
    end
  end
  if not arrival then
    -- Coalesce duplicate text only during incomplete arrival recovery. Once
    -- identity and contents are known, another walk must retire that roster.
    if currentArrival and currentArrival.entered and currentArrival.direction == heading
        and not (currentArrival.info and room.ready) then return end
    arrival = {direction = heading, contextId = newContext()}
    arrivals[#arrivals + 1] = arrival
  end
  arrival.entered, arrival.direction = true, heading
  acknowledgeSubmission(arrival)
  -- Every walk replaces the preceding heading. Tracked walks may still pair
  -- with Info received since this outgoing batch began, including a packet
  -- for the next queued walk delivered before its text. onMovement clears
  -- those packets for a later batch; a new unhinted arrival clears them here.
  if not arrival.hinted and not arrival.info then freshInfo = nil end
  headingFrame = {arrival = arrival}
  recoveryReason = not arrival.info and 'Waiting for the native heading and fresh Room.Info.' or nil
  confirmed(nil, arrival)
end

function room.onHeading(name, number)
  local frame = headingFrame
  if not frame or frame.closed or frame.headingSeen then return end
  frame.headingSeen, frame.name, frame.num = true, roomName(name), id(number)
  local arrival = frame.arrival
  if arrival.identity and headingConflicts(arrival, arrival.identity) then
    blockHeadingConflict(arrival)
  end
  recoverHeading()
end

function room.onWrongDir(payload)
  local heading = direction(payload)
  if not heading or pendingMoves == 0 then return end
  local failed
  for i, arrival in ipairs(arrivals) do
    if arrival.hinted and not arrival.info and not arrival.entered
        and arrival.direction == heading then failed = i; break end
  end
  if not failed then return end
  headingFrame, freshInfo, recoveryReason = nil, nil, nil
  table.remove(arrivals, failed)
  pendingMoves = pendingMoves - 1
  rejectedReason = nil
  expectedPath()
  local unresolvedEntry
  for i = #arrivals, 1, -1 do
    if arrivals[i].entered and not arrivals[i].info then
      unresolvedEntry = arrivals[i]; break
    end
  end
  if pendingMoves == 0 and unresolvedEntry then
    -- Failure did not undo an earlier successful entry. Rebase its recovery
    -- after the failed command's invalidation, without restoring an old room.
    unresolvedEntry.generation = nil
    confirmed(nil, unresolvedEntry)
  elseif pendingMoves == 0 and lastIdentity then
    local arrival = {info = true, contextId = room.contextId}
    arrivals = {arrival}
    confirmed(lastIdentity, arrival)
  else
    invalidate()
    currentArrival, awaitingArrival = nil, true
    if hunting() then room.request('Movement awaiting Room.Info') end
    changed()
  end
end

function room.onMovementBlocked()
  -- The latest pure movement packet does not erase an earlier command whose
  -- response is still ambiguous. Never use that refusal to restore old targets.
  if not movementOnlyPacket or ambiguousSubmission or pendingMoves == 0 then return false end
  for _, arrival in ipairs(arrivals) do
    if arrival.hinted and not arrival.info and not arrival.entered then
      room.onWrongDir(arrival.direction)
      return true
    end
  end
  return false
end

function room.onInfo(payload)
  if type(payload) ~= 'table' then return end
  local number = id(payload.num)
  if not number then return end
  local identity = {num = number, area = area(payload.area), name = roomName(payload.name)}
  lastReceivedRoom = number
  if pendingMoves > 0 or headingFrame then
    freshInfo = {identity = identity, name = roomName(payload.name)}
  end
  if type(payload.exits) == 'table' then
    local exits, ambiguous = {}, {}
    for heading, destination in pairs(payload.exits) do
      local normalized, target = direction(heading), id(destination)
      if normalized and target and not ambiguous[normalized] then
        if exits[normalized] and exits[normalized] ~= target then
          exits[normalized], ambiguous[normalized] = nil, true
        else
          exits[normalized] = target
        end
      end
    end
    exitsByRoom[number] = exits
  end
  expectedPath()
  -- Complete current-frame proof before an ordinary ordered match can assign
  -- this packet to an older arrival and return with the current one pending.
  if recoverHeading() then return end
  local arrival, arrivalIndex, firstIndex
  if pendingMoves > 0 then
    for i, candidate in ipairs(arrivals) do
      if not candidate.info then firstIndex = i; break end
    end
    -- A later destination can acknowledge skipped packets only when the
    -- whole cached path is explicit and every skipped entry succeeded.
    local proven = true
    for i = firstIndex, #arrivals do
      local candidate = arrivals[i]
      if not candidate.info then
        if not candidate.expected then proven = false end
        -- A later unentered repeat cannot supersede an earlier match: that
        -- packet may still acknowledge the earlier visit to the same room.
        if proven and candidate.expected == number and (not arrival or candidate.entered) then
          arrival, arrivalIndex = candidate, i
        end
        if not candidate.entered then break end
      end
    end
  end
  -- LOOK and duplicate updates also emit Room.Info. Repeating the last known
  -- identity does not prove that a queued movement has executed. Otherwise a
  -- look&&n reply could re-enable attacks in the room we are about to leave.
  if (pendingMoves > 0 or (currentArrival and currentArrival.entered and not room.num))
      and lastIdentity and number == lastIdentity.num
      and not (arrival and arrival.entered) then
    if payload.area ~= nil then lastIdentity.area = identity.area end
    rejectedReason = 'Repeated identity without a confirmed return path.'
    if recoverHeading() then return end
    changed()
    return
  end
  if pendingMoves > 0 then
    if not arrival then
      arrival, arrivalIndex = arrivals[firstIndex], firstIndex
      if arrival.expected and arrival.expected ~= number then
        rejectedReason = 'Room.Info does not match the expected movement destination.'
        if recoverHeading() then return end
        changed()
        return
      end
    end
    if headingConflicts(arrival, identity) then blockHeadingConflict(arrival); return end
    for i = firstIndex, arrivalIndex do
      local candidate = arrivals[i]
      if not candidate.info then
        candidate.info = true
        if candidate.hinted then pendingMoves = pendingMoves - 1 end
      end
      acknowledgeSubmission(candidate)
    end
    arrival.identity = identity
    lastIdentity = identity
    rejectedReason, recoveryReason = nil, nil
    if pendingMoves == 0 then
      confirmed(identity, arrival)
    else
      confirmed(nil, arrival)
    end
    return
  end
  if number ~= room.num then
    for _, candidate in ipairs(arrivals) do
      if not candidate.info then arrival = candidate; break end
    end
    if not arrival then
      -- The first identity is a snapshot, not evidence of a new arrival. Only
      -- a genuine transition may pair with walk text that has not arrived yet.
      local transition = lastIdentity ~= nil
      arrival = {textEligible = transition,
        contextId = transition and newContext() or room.contextId}
      -- No queued command needs older arrival acknowledgements now.
      arrivals = {arrival}
    end
    if headingConflicts(arrival, identity) then blockHeadingConflict(arrival); return end
    arrival.info, arrival.identity, lastIdentity = true, identity, identity
    rejectedReason, recoveryReason = nil, nil
    confirmed(identity, arrival)
    return
  elseif payload.area ~= nil then
    room.area = identity.area
  else
    identity.area = room.area
  end
  lastIdentity = identity
  rejectedReason = nil
  changed()
end

function room.onPrompt()
  if headingFrame and not headingFrame.headingSeen then
    headingFrame.closed = true
    if not headingFrame.arrival.info then
      recoveryReason = 'The successful walk frame closed before a native heading.'
    end
  end
  -- Only unhinted Info-first correlation expires at a prompt. An outgoing
  -- movement token still owns its eventual walk text across prompt boundaries.
  for _, arrival in ipairs(arrivals) do
    if arrival.info and not arrival.hinted then arrival.textEligible = false end
  end
end

function room.onList(payload)
  if not room.num or type(payload) ~= 'table'
      or payload.location ~= 'room' or type(payload.items) ~= 'table' then return end
  local items, order = {}, {}
  for _, value in ipairs(payload.items) do
    local item, key = record(value)
    if item then
      if not items[key] then order[#order + 1] = key end
      items[key] = item
    end
  end
  local old = room.items
  room.cancelRefresh()
  room.items, room.order, room.ready, room.phase = items, order, true, 'ready'
  room.processingList = true
  for key in pairs(old) do
    if not items[key] then
      room.retired[key] = true
      if dem.hunt then dem.hunt.onRemoved(key) end
    end
  end
  room.processingList = false
  changed()
end

local function delta(payload, liveAdd)
  if not room.num or type(payload) ~= 'table'
      or payload.location ~= 'room' then return end
  local value = payload.item
  local key = type(value) == 'table' and id(value.id) or nil
  if not key then return end
  local item = record(value, room.items[key])
  if not item then return end
  if not room.items[key] then room.order[#room.order + 1] = key end
  room.items[key] = item
  if liveAdd then room.retired[key] = nil end
  changed()
end

function room.onAdd(payload) delta(payload, true) end
function room.onUpdate(payload) delta(payload, false) end

function room.onRemove(payload)
  if not room.num or type(payload) ~= 'table'
      or payload.location ~= 'room' then return end
  local value = payload.item
  local key = id(type(value) == 'table' and value.id or value)
  if not key then return end
  room.items[key], room.retired[key] = nil, true
  for i = #room.order, 1, -1 do
    if room.order[i] == key then table.remove(room.order, i) end
  end
  if dem.hunt then dem.hunt.onRemoved(key) end
  changed()
end

-- This lookup may use a known same-room snapshot while its refresh is pending.
-- It is for target ownership/removal only; resolve() below gates all attacks.
function room.identify(reference, preferredKey, eligibleOnly)
  if not room.num then return nil, 'The room identity is not ready.' end
  local valid = dem.validReference(reference)
  if not valid then return nil, 'Invalid denizen reference.' end
  local ref, found, foundKey = valid:lower(), nil, nil
  -- A native identity must never redirect to another denizen's numeric name word.
  local exact = room.items[ref]
  if exact or room.retired[ref] then
    if room.retired[ref] or not room.living(exact) then
      return nil, 'That denizen is not in the current room.'
    end
    if eligibleOnly and not room.eligible(exact) then
      return nil, 'That denizen is protected and cannot be hunted.'
    end
    return exact, ref
  end
  local preferred, preferredItem, protected = id(preferredKey), nil, false
  for _, key in ipairs(room.order) do
    local item = room.items[key]
    if item and not room.retired[key] and room.living(item) and room.matchesReference(item, valid) then
      if eligibleOnly and not room.eligible(item) then
        protected = true
      else
        if not found then found, foundKey = item, key end
        if key == preferred then preferredItem = item end
      end
    end
  end
  if preferredItem then return preferredItem, preferred end
  if not found then
    if protected then return nil, 'That denizen is protected and cannot be hunted.' end
    return nil, 'That denizen is not in the current room.'
  end
  return found, foundKey
end

function room.resolve(reference, preferredKey)
  if not room.ready then return nil, 'The room roster is not ready.' end
  return room.identify(reference, preferredKey, true)
end
