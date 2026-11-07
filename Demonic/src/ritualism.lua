dem.ritualism = {duality = true, costs = {fire = 9, ice = 9}}
local ritualism = dem.ritualism

local function validSymbols(symbols)
  if type(symbols) ~= 'table' or #symbols < 1 or #symbols > 2 then
    return nil, 'Trace requires one or two symbols.'
  end
  for i = 1, #symbols do
    if type(symbols[i]) ~= 'string' or not symbols[i]:match('^[A-Za-z][A-Za-z0-9_%-]*$') then
      return nil, 'Invalid ritualism symbol.'
    end
  end
  return true
end

function ritualism.buildTrace(symbols, ref)
  local ok, err = validSymbols(symbols)
  if not ok then return nil, err end
  if #symbols == 2 and not ritualism.duality then return nil, 'Duality is not learned.' end
  local target, targetErr = dem.validReference(ref)
  if not target then return nil, targetErr end
  return 'trace ' .. table.concat(symbols, ' ') .. ' ' .. target
end

function ritualism.manaCost(symbols)
  if not validSymbols(symbols) then return nil end
  local total = 0
  for _, symbol in ipairs(symbols) do
    local cost = ritualism.costs[symbol]
    if type(cost) ~= 'number' then return nil end
    total = total + cost
  end
  return total
end
