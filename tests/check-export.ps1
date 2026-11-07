$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
[xml]$package = Get-Content -LiteralPath (Join-Path $root 'Demonic/Demonic.xml') -Raw
$order = @($package.SelectNodes('//ScriptPackage/*[self::Script or self::ScriptGroup]/name') | ForEach-Object { $_.InnerText })
if (($order -join '|') -cne 'System|Diabolist|Initialize Demonic') { throw 'Export load order must be System, Diabolist, Initialize Demonic.' }
$defs = @($package.SelectNodes('//AliasPackage/AliasGroup[name="Diabolist"]/AliasGroup[name="Ritualism"]/Alias[name="Defs"]'))
if ($defs.Count -ne 1 -or $defs[0].regex -cne '^ddef$' -or $defs[0].script -cne 'dem.defences.toggle()' -or $defs[0].GetAttribute('isActive') -cne 'yes') { throw 'Missing or incorrect Defs alias.' }
$ceased = $package.SelectSingleNode('//TriggerPackage//Trigger[name="Nightfall cease"]')
if (!$ceased -or $ceased.regexCodeList.string -cne '^The darkness around you dissipates\.$') { throw 'Incorrect Nightfall cessation pattern.' }
$fixtures = @{
    'Vitality activated' = 'You sketch the Anae-antarea symbol in the air, and a feeling of anticipation fills the air as a glow surrounds you momentarily.'
    'Demon regeneration' = 'You demand aid from your Ouroboros, and it it surrounds you with a glowing red ring.'
    'Demon armor' = 'You ask your Ouroboros for its protection, and it summons a thin black protecting sheen over you.'
    'Missing ouroboros' = 'With a disimpassioned gesture, you banish your Ouroboros back to the Pit from which it came.'
    'Summoned ouroboros' = 'You call out, ordering your Ouroboros to return to serve your will.'
    'Soulmask' = 'Your Ouroboros glows faintly, and you feel your presence masked from prying eyes.'
    'Syphon ceased' = 'Your Ouroboros ceases its disease syphoning.'
    'Syphoning on' = 'You implore your Ouroboros to help its beloved master, and the heat of its power begins to wash over you.'
    'Nightfall defence' = 'Concentrating deeply, you call forth an all-encompassing darkness that rapidly surrounds you.'
    'Nightfall cease' = 'The darkness around you dissipates.'
}
foreach ($name in $fixtures.Keys) {
    $nodes = @($package.SelectNodes(('//TriggerPackage/TriggerGroup[name="Diabolist"]//Trigger[name="{0}"]' -f $name)))
    if ($nodes.Count -ne 1 -or $nodes[0].GetAttribute('isActive') -cne 'yes') { throw ('Missing or duplicate active class trigger: ' + $name) }
    $pattern = $nodes[0].regexCodeList.string
    if ($nodes[0].regexCodePropertyList.integer -cne '1' -or $fixtures[$name] -cnotmatch $pattern) { throw ('Class trigger rejects its game message: ' + $name) }
    foreach ($invalid in @(('prefix ' + $fixtures[$name]), ($fixtures[$name] + ' extra'), $fixtures[$name].Replace('.', '!'))) {
        if ($invalid -cmatch $pattern) { throw ('Class trigger matches unrelated text: ' + $name) }
    }
}
if ($fixtures['Nightfall defence'] -cmatch $ceased.regexCodeList.string) { throw 'Nightfall activation also matches cessation.' }
foreach ($node in $package.SelectNodes('//script[string-length(text()) > 0]')) {
    if ($node.InnerText -cmatch '(?<![\w.])(mal|nightfall)\.') { throw ('Undefined legacy global in ' + $node.ParentNode.name) }
}
Write-Output 'Export startup order, Defs alias, Nightfall cessation and legacy globals: PASS'
