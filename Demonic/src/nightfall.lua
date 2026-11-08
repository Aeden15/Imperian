dem.nightfall = {
  types = {'vigorous', 'whispering', 'translucent', 'fiery', 'midnight', 'glowing', 'reflective', 'ethereal'},
  limits = {simultaneous = 4, charges = 5, inactivitySeconds = 30}
}
local nightfall = dem.nightfall
local revisions, snapshot

function nightfall.resetWraiths()
  nightfall.wraiths, revisions, snapshot = {}, {}, nil
  for _, kind in ipairs(nightfall.types) do
    nightfall.wraiths[kind], revisions[kind] = {}, 0
  end
end
nightfall.resetWraiths()

local function changed(kind)
  revisions[kind] = revisions[kind] + 1
end

local function clearInstance(wraith)
  wraith.id, wraith.charges, wraith.target, wraith.location = nil, nil, nil, nil
end

function nightfall.onMaterialised(kind)
  local wraith = nightfall.wraiths[kind]
  if not wraith then return false end
  if wraith.present ~= true then clearInstance(wraith) end
  wraith.present = true
  changed(kind)
  return true
end

function nightfall.onCharges(kind, count)
  local wraith = nightfall.wraiths[kind]
  count = tonumber(count)
  if not wraith or not count or count < 0 or count > nightfall.limits.charges or count % 1 ~= 0 then return false end
  if wraith.present ~= true then clearInstance(wraith) end
  wraith.present, wraith.charges = true, count
  changed(kind)
  return true
end

function nightfall.onLostCharges(kind)
  local wraith = nightfall.wraiths[kind]
  if not wraith then return false end
  wraith.charges = 0
  changed(kind)
  return true
end

function nightfall.onVanished(kind)
  local wraith = nightfall.wraiths[kind]
  if not wraith then return false end
  clearInstance(wraith)
  wraith.present = false
  changed(kind)
  return true
end

function nightfall.beginSnapshot(header)
  snapshot = nil
  if type(header) ~= 'string' then return false end
  local columns, previous = {}, 0
  for i, name in ipairs({'Type', 'Enabled', 'ID', 'Charges', 'Target', 'Location'}) do
    local start = header:find(name, previous + 1, true)
    if not start then return false end
    columns[i], previous = start, start
  end
  snapshot = {columns = columns, rows = {}, count = 0, valid = true}
  return true
end

local function optional(value)
  if value ~= '' and value ~= '---' then return value end
end

function nightfall.onSnapshotRow(line)
  if not snapshot or type(line) ~= 'string' then return false end
  local fields = {}
  for i, start in ipairs(snapshot.columns) do
    fields[i] = dem.trim(line:sub(start, snapshot.columns[i + 1] and snapshot.columns[i + 1] - 1 or #line))
  end
  local kind = fields[1]:lower()
  if not nightfall.wraiths[kind] or snapshot.rows[kind] or (fields[2] ~= 'Yes' and fields[2] ~= 'No') then
    snapshot.valid = false; return false
  end
  local row = {enabled = fields[2] == 'Yes', revision = revisions[kind]}
  -- Missing columns are not an explicit absent-instance marker.
  if fields[3] == '' then snapshot.valid = false; return false end
  local id = optional(fields[3])
  if id then
    local charges = tonumber(fields[4])
    if fields[6] == '' or not id:match('^%d+$') or id:match('^0+$') or not charges or charges < 0
        or charges > nightfall.limits.charges or charges % 1 ~= 0 then
      snapshot.valid = false; return false
    end
    row.present, row.id, row.charges = true, id, charges
    row.target, row.location = optional(fields[5]), optional(fields[6])
  else
    if optional(fields[4]) or optional(fields[5]) or optional(fields[6]) then snapshot.valid = false; return false end
    row.present = false
  end
  snapshot.rows[kind], snapshot.count = row, snapshot.count + 1
  return true
end

function nightfall.finishSnapshot()
  local capture = snapshot
  snapshot = nil
  if not capture or not capture.valid or capture.count ~= #nightfall.types then return false end
  local ids, present = {}, 0
  for _, row in pairs(capture.rows) do
    if row.id then
      if ids[row.id] then return false end
      ids[row.id], present = true, present + 1
    end
  end
  if present > nightfall.limits.simultaneous then return false end
  for kind, row in pairs(capture.rows) do
    -- A later live message owns its type even when an older table row exists.
    if revisions[kind] == row.revision then
      local wraith = nightfall.wraiths[kind]
      wraith.enabled, wraith.present = row.enabled, row.present
      wraith.id, wraith.charges, wraith.target, wraith.location = row.id, row.charges, row.target, row.location
      changed(kind)
    end
  end
  return true
end

function dem.nightfall.buildDefence(name)
  if name == 'nightfall' then return 'nightfall' end
end
