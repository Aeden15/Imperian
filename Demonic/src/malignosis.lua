dem.malignosis = {}
local commands = {
  ouroboros = 'summon ouroboros', armor = 'demon armor', regeneration = 'demon regeneration',
  soulmask = 'demon soulmask', syphon = 'demon syphon'
}

function dem.malignosis.buildDefence(name)
  return commands[name]
end
