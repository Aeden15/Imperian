$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
[xml]$package = Get-Content -LiteralPath (Join-Path $root 'Demonic/Demonic.xml') -Raw
$order = @($package.SelectNodes('//ScriptPackage/*[self::Script or self::ScriptGroup]/name') | ForEach-Object { $_.InnerText })
if (($order -join '|') -cne 'System|Diabolist|Summoner|Initialize Demonic') { throw 'Incorrect export load order.' }
$defs = @($package.SelectNodes('//AliasPackage//Alias[regex="^ddef$" and not(ancestor-or-self::*[@isActive="no"])]'))
if ($defs.Count -ne 1 -or $defs[0].regex -cne '^ddef$' -or $defs[0].script -cne 'dem.defences.run()' -or $defs[0].GetAttribute('isActive') -cne 'yes') { throw 'Missing or incorrect Defs alias.' }
if (!$defs[0].SelectSingleNode('ancestor::AliasGroup[name="Summoner"]')) { throw 'Active Defs alias must be under Summoner.' }
$legacyFolders = @($package.SelectNodes('/*/*/*[name="Diabolist"]'))
if ($legacyFolders.Count -ne 3) { throw 'Missing archived Diabolist folders.' }
$legacyGuard = 'if not dem or dem.profession ~= "diabolist" then return end' + "`n"
foreach ($folder in $legacyFolders) {
    if ($folder.GetAttribute('isActive') -cne 'no') { throw 'Diabolist folder must be disabled.' }
    foreach ($script in $folder.SelectNodes('.//script[string-length(text()) > 0]')) {
        if (!$script.InnerText.StartsWith($legacyGuard, [StringComparison]::Ordinal)) { throw 'Diabolist Lua is missing its profession guard.' }
        # Check archived handler bodies below, after proving the guards exist.
        $script.InnerText = $script.InnerText.Substring($legacyGuard.Length)
    }
}
$summonerDefences = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="Summoner"]/TriggerGroup[name="Defences"]')
if (!$summonerDefences -or $summonerDefences.SelectNodes('Trigger').Count -ne 4) { throw 'Summoner defence triggers must be siblings.' }
$mindseyeFolder = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Curing"]/TriggerGroup[name="Defences"]')
foreach ($entry in @(@('Mindseye activated', 'true'), @('Mindseye stripped', 'false'))) {
    $node = $mindseyeFolder.SelectSingleNode(('Trigger[name="{0}"]' -f $entry[0]))
    if (!$node -or $node.script -cne ('dem.defences.setActive("mindseye", {0})' -f $entry[1])) { throw 'Mindseye must use shared defence state.' }
}
$ceased = $package.SelectSingleNode('//TriggerPackage//Trigger[name="Nightfall cease"]')
if (!$ceased -or $ceased.regexCodeList.string -cne '^The darkness around you dissipates\.$') { throw 'Incorrect Nightfall cessation pattern.' }
$fixtures = @{
    'Vitality activated' = 'You sketch the Anae-antarea symbol in the air, and a feeling of anticipation fills the air as a glow surrounds you momentarily.'
    'Vitality consumed' = 'Your beaten body suddenly starts glowing brightly as the symbol of vitality takes effect.'
    'Vitality cooldown' = 'You cannot use the Anae-antarea symbol again so soon.'
    'Vitality ready' = 'You can again use the Anae-Antarea symbol.'
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
$ritualismFolder = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="Diabolist"]/TriggerGroup[name="Ritualism"]')
foreach ($name in @('Vitality consumed','Vitality cooldown','Vitality ready')) {
    if (!$ritualismFolder.SelectSingleNode(('Trigger[name="{0}"]' -f $name))) { throw ('Misplaced trigger: ' + $name) }
}
$wraithFolder = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="Diabolist"]/TriggerGroup[name="Nightfall"]/TriggerGroup[name="Wraiths"]')
if (!$wraithFolder -or $wraithFolder.SelectNodes('Trigger').Count -ne 6) { throw 'Missing or duplicate Nightfall/Wraiths triggers.' }
$eventContracts = @{
    'Wraith materialised' = @('A {0} wraith suddenly materialises out of thin air next to you, its shape unfocused and blurry.', 'dem.nightfall.onMaterialised(matches[2])')
    'Wraith charges' = @('A {0} wraith now has 1 charge.', 'dem.nightfall.onCharges(matches[2], matches[3])')
    'Wraith lost charges' = @('A {0} wraith has lost its accumulated charges.', 'dem.nightfall.onLostCharges(matches[2])')
    'Wraith vanished' = @('Your {0} wraith freezes in mid-air for a moment, then disappears with a silent ''pop''.', 'dem.nightfall.onVanished(matches[2])')
}
foreach ($name in $eventContracts.Keys) {
    $nodes = @($wraithFolder.SelectNodes(('Trigger[name="{0}"]' -f $name)))
    if ($nodes.Count -ne 1 -or $nodes[0].GetAttribute('isActive') -cne 'yes' -or $nodes[0].script -cne $eventContracts[$name][1] -or $nodes[0].regexCodePropertyList.integer -cne '1') { throw ('Incorrect wraith contract: ' + $name) }
    $pattern = $nodes[0].regexCodeList.string
    foreach ($kind in @('vigorous','whispering','translucent','fiery','midnight','glowing','reflective','ethereal')) {
        $line = $eventContracts[$name][0] -f $kind
        if ($line -cnotmatch $pattern -or $Matches[1] -cne $kind) { throw ('Wraith type capture failed: ' + $name + ' ' + $kind) }
        foreach ($invalid in @(('prefix '+$line),($line+' extra'),($eventContracts[$name][0] -f 'imaginary'))) {
            if ($invalid -cmatch $pattern) { throw ('Wraith event accepts unrelated text: ' + $name) }
        }
        if ($name -ceq 'Wraith charges') {
            foreach ($count in 0..5) {
                $line = 'A '+$kind+' wraith now has '+$count+' '+$(if ($count -eq 1) {'charge.'} else {'charges.'})
                if ($line -cnotmatch $pattern -or $Matches[2] -cne "$count") { throw 'Charge capture failed.' }
            }
            foreach ($count in @('-1','6','99','1.5')) {
                if (('A '+$kind+' wraith now has '+$count+' charges.') -cmatch $pattern) { throw 'Invalid charge count accepted.' }
            }
        }
    }
}
$materialised = $wraithFolder.SelectSingleNode('Trigger[name="Wraith materialised"]')
if ('A whispering wraith suddenly materialises out of thin air next to you, its shape unfocused and ' -cnotmatch $materialised.regexCodeList.string) { throw 'Wrapped materialisation is not recognised.' }
$statusHeader = $wraithFolder.SelectSingleNode('Trigger[name="Wraith status header"]')
$statusRow = $wraithFolder.SelectSingleNode('Trigger[name="Wraith status row"]')
if (!$statusHeader -or 'Type          Enabled    ID        Charges   Target           Location' -cnotmatch $statusHeader.regexCodeList.string -or $statusHeader.script -cne 'dem.nightfall.beginSnapshot(line)') { throw 'Incorrect wraith header trigger.' }
if (!$statusRow -or 'Whispering    Yes        387609    1         ---              here' -cnotmatch $statusRow.regexCodeList.string -or $statusRow.script -cne 'dem.nightfall.onSnapshotRow(line)') { throw 'Incorrect wraith row trigger.' }
foreach ($node in $package.SelectNodes('//script[string-length(text()) > 0]')) {
    # Runtime modules may legitimately use a local alias for their dem namespace.
    if ($node.ParentNode.LocalName -eq 'Trigger' -and $node.InnerText -cmatch '(?<![\w.])(mal|nightfall)\.') { throw ('Undefined legacy global in ' + $node.ParentNode.name) }
}
Write-Output 'Export startup order, Summoner defences and Diabolist archive: PASS'
