$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$xmlPath = Join-Path $root 'Demonic/Demonic.xml'
$originalHash = (Get-FileHash -LiteralPath $xmlPath -Algorithm SHA256).Hash
& (Join-Path $root 'tools/build.ps1') | Out-Null
$firstHash = (Get-FileHash -LiteralPath $xmlPath -Algorithm SHA256).Hash
& (Join-Path $root 'tools/build.ps1') | Out-Null
if ((Get-FileHash -LiteralPath $xmlPath -Algorithm SHA256).Hash -ne $firstHash) { throw 'Package rebuild is not deterministic.' }
if ($firstHash -ne $originalHash) { throw 'Bundled XML was stale. Rebuild, then rerun tests.' }
if ((Get-Item -LiteralPath $xmlPath).Length -gt 1048576) { throw 'Generated package exceeds expected size.' }
[xml]$package = Get-Content -LiteralPath $xmlPath -Raw
[xml]$template = Get-Content -LiteralPath (Join-Path $root 'tools/Demonic.template.xml') -Raw
if ($package.SelectNodes('//Trigger/Trigger | //Trigger/TriggerGroup').Count -ne 0) { throw 'Nested generated triggers.' }
$scripts = @($package.SelectNodes('//ScriptPackage//Script/script'))
$sourceFiles = @{
    'Core' = 'core'; 'Targeting' = 'targeting'; 'Balances and Vitals' = 'balances'
    'Room Tracking' = 'room'; 'Hunt Controller' = 'hunt'
    'Ritualism Commands' = 'ritualism'; 'Initialize Demonic' = 'bootstrap'
}
if ($scripts.Count -ne $sourceFiles.Count) { throw 'Unexpected embedded Script count.' }
# The export is flat: Package Manager supplies the single Demonic wrapper.
# Compare the entire non-owned skeleton, including group attributes/metadata,
# rather than merely accepting folder paths that happen to contain our leaves.
$preserved = $package.Clone()
$owned = @{
    Script = @($sourceFiles.Keys)
    Alias = @('Hunt mode','Hunt add','Hunt remove','Hunt list','Hunt status','Hunt limits','Targeting')
    Trigger = @('Balance loss duration','Equilibrium loss duration','Balance regained','Equilibrium regained','Balance unavailable','Equilibrium unavailable','Prompt readiness','Denizen slain','Target absent','Grace blocks attack','Room entered','Room heading')
}
foreach ($tag in $owned.Keys) {
    foreach ($node in @($preserved.SelectNodes(('//' + $tag)))) {
        if ($node.SelectSingleNode('name').InnerText -cin $owned[$tag]) { [void]$node.ParentNode.RemoveChild($node) }
    }
}
if ($preserved.OuterXml -cne $template.OuterXml) { throw 'Build changed the preserved export layout or metadata.' }
foreach ($kind in @('Trigger','Alias','Script')) {
    $top = @($package.SelectNodes(('//{0}Package/{0}Group/name' -f $kind)) | ForEach-Object { $_.InnerText })
    $expected = if ($kind -eq 'Script') { 'System|Diabolist' } else { 'Diabolist|System' }
    if (($top -join '|') -cne $expected) { throw ('Flat export roots changed: ' + $kind) }
    if ($package.SelectNodes(('//{0}Package//{0}Group[name="Demonic"]' -f $kind)).Count -ne 0) {
        throw ('Duplicate inner Demonic folder: ' + $kind)
    }
}
$sharedOrder = @($package.SelectNodes('//ScriptPackage/ScriptGroup[name="System"]/*[self::Script or self::ScriptGroup]/name') | ForEach-Object { $_.InnerText })
if (($sharedOrder[0..2] -join '|') -cne 'Core|Targeting|Balances and Vitals') { throw 'Shared scripts must load before child modules.' }
$lastScript = $package.SelectSingleNode('//ScriptPackage/*[self::Script or self::ScriptGroup][last()]')
if ($lastScript.LocalName -cne 'Script' -or $lastScript.SelectSingleNode('name').InnerText -cne 'Initialize Demonic') {
    throw 'Initialize Demonic must be the final standalone script.'
}
$config = Get-Content -LiteralPath (Join-Path $root 'Demonic/config.lua') -Raw
if ($config -cnotmatch '(?m)^created = "2026-11-07T01:33:06-06:00"\r?$') { throw 'Export creation timestamp was not preserved.' }
if ($config -cnotmatch '(?m)^mpackage = \[\[Demonic\]\]\r?$' -or $config -cnotmatch '(?m)^version = \[\[0\.1\.6\]\]\r?$' -or $config -cnotmatch '(?s)description = \[\[Shared targeting.+?\]\]') {
    throw 'Package version or description is missing.'
}
foreach ($name in $sourceFiles.Keys) {
    $nodes = @($package.SelectNodes(('//ScriptPackage//Script[name="{0}"]/script' -f $name)))
    $source = Get-Content -LiteralPath (Join-Path $root ('Demonic/src/{0}.lua' -f $sourceFiles[$name])) -Raw
    if ($nodes.Count -ne 1 -or $nodes[0].InnerText -cne $source) {
        throw ('Embedded Script does not match its source: ' + $name)
    }
}
$targetFolder = $package.SelectSingleNode('//AliasPackage/AliasGroup[name="System"]/AliasGroup[name="Targeting"]')
if (!$targetFolder) { throw 'Targeting alias folder is missing.' }
$targetNodes = @($targetFolder.SelectNodes('.//Alias'))
if ($targetNodes.Count -ne 1) { throw 'Targeting must contain exactly one alias.' }
$targetAlias = $targetNodes[0]
if ($targetAlias.name -cne 'Targeting' -or $targetAlias.regex -cne '^t (\w+)$' -or $targetAlias.script -cne 'dem.targeting.set(matches[2])') {
    throw 'Targeting alias must use the exact approved name, regex, and script.'
}
if ($package.SelectNodes('//Alias[@isActive="yes" and name="Targeting"]').Count -ne 1) { throw 'Expected one active Targeting alias.' }
if ($package.SelectNodes('//Alias[@isActive="yes" and regex="^hunt$"]').Count -ne 1) { throw 'Expected one active Hunt mode alias.' }
if ($package.SelectNodes('//Alias[name="Target player" or name="Target denizen" or name="Clear target"]').Count -ne 0) {
    throw 'Legacy targeting aliases remain in the package.'
}
foreach ($command in @('t ant','t ant427409','t 427409','t clear')) {
    if ($command -cnotmatch $targetAlias.regex) { throw ('Targeting alias rejects: ' + $command) }
}
foreach ($command in @('t player Name','t denizen ant','t ant extra',' t ant','t  ant','t ant ')) {
    if ($command -cmatch $targetAlias.regex) { throw ('Targeting alias incorrectly accepts: ' + $command) }
}
$statusNodes = @($package.SelectNodes('//AliasPackage/AliasGroup[name="System"]/AliasGroup[name="Autobasher"]/Alias[name="Hunt status"]'))
if ($statusNodes.Count -ne 1) { throw 'Hunt status alias is missing or duplicated.' }
$statusAlias = $statusNodes[0]
if ($statusAlias.regex -cne '^hunt status(?: (debug))?$' -or $statusAlias.script -cne 'dem.hunt.status(matches[2] == "debug")') {
    throw 'Hunt status alias must use the exact approved regex and script.'
}
if ($package.SelectNodes('//Alias[@isActive="yes" and name="Hunt status"]').Count -ne 1 -or $statusAlias.GetAttribute('isActive') -cne 'yes') {
    throw 'Expected one active Hunt status alias in System/Autobasher.'
}
foreach ($command in @('hunt status','hunt status debug')) {
    if ($command -cnotmatch $statusAlias.regex) { throw ('Hunt status alias rejects: ' + $command) }
}
foreach ($command in @('hunt status extra','hunt status debug extra','hunt status  debug','hunt statusdebug',' hunt status','hunt status ')) {
    if ($command -cmatch $statusAlias.regex) { throw ('Hunt status alias incorrectly accepts: ' + $command) }
}
$enteredNodes = @($package.SelectNodes('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Autobasher"]/Trigger[name="Room entered"]'))
if ($enteredNodes.Count -ne 1) { throw 'Room entered trigger is missing or duplicated.' }
$enteredTrigger = $enteredNodes[0]
$enteredPatterns = @($enteredTrigger.SelectNodes('regexCodeList/string'))
$enteredTypes = @($enteredTrigger.SelectNodes('regexCodePropertyList/integer'))
if ($enteredPatterns.Count -ne 1 -or $enteredPatterns[0].InnerText -cne '^You\s+walk\s+([A-Za-z]+)(?=\s|[.,!?;:]|$)' -or $enteredTrigger.script -cne 'dem.room.onEntered(matches[2])' -or $enteredTypes.Count -ne 1 -or $enteredTypes[0].InnerText -cne '1') {
    throw 'Room entered trigger must use the exact approved regex, type, and script.'
}
if ($package.SelectNodes('//Trigger[@isActive="yes" and name="Room entered"]').Count -ne 1 -or $enteredTrigger.GetAttribute('isActive') -cne 'yes') {
    throw 'Expected one active Room entered trigger in System/Autobasher.'
}
foreach ($direction in @('north','northeast','east','southeast','south','southwest','west','northwest','up','down','in','out')) {
    foreach ($walkLine in @(
        ('You walk ' + $direction + '.')
        ('You  walk  ' + $direction)
        ('You walk ' + $direction + '!')
        ('You walk ' + $direction + ', following the path.')
        ('You walk ' + $direction + '; the trail continues.')
        ('You walk ' + $direction + ': onward.')
        ('You walk ' + $direction + '?')
        ('You walk ' + $direction + ' to "Ant colony".')
        ("You walk " + $direction + " to 'The scorched beginnings of an ascent'.")
        ('You walk ' + $direction + ' (following your automatic path).')
    )) {
        if ($walkLine -cnotmatch $enteredPatterns[0].InnerText -or $Matches[1] -cne $direction) {
            throw ('Room entered trigger rejects or miscaptures: ' + $walkLine)
        }
    }
}
foreach ($walkLine in @('prefix You walk northeast.','you walk northeast.','You walked northeast.','You walk northeast42.','You walk north-east.','You walk 42.','You walk .','You walk')) {
    if ($walkLine -cmatch $enteredPatterns[0].InnerText) { throw ('Room entered trigger incorrectly accepts: ' + $walkLine) }
}
# The approved regex captures words; the Lua handler validates supported directions.
if ('You walk quietly.' -cnotmatch $enteredPatterns[0].InnerText -or $Matches[1] -cne 'quietly') {
    throw 'Room entered must leave unsupported-word validation to the Lua handler.'
}
$headingNodes = @($package.SelectNodes('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Autobasher"]/Trigger[name="Room heading"]'))
if ($headingNodes.Count -ne 1) { throw 'Room heading trigger is missing or duplicated.' }
$headingTrigger = $headingNodes[0]
$headingPatterns = @($headingTrigger.SelectNodes('regexCodeList/string'))
$headingTypes = @($headingTrigger.SelectNodes('regexCodePropertyList/integer'))
if ($headingPatterns.Count -ne 1 -or $headingPatterns[0].InnerText -cne '^(.+?)\.\s+(\d+)(?:\s+\([^)]*\))?\.?$' -or $headingTrigger.script -cne 'dem.room.onHeading(matches[2], matches[3])' -or $headingTypes.Count -ne 1 -or $headingTypes[0].InnerText -cne '1') {
    throw 'Room heading trigger must use the exact approved regex, type, and script.'
}
if ($package.SelectNodes('//Trigger[@isActive="yes" and name="Room heading"]').Count -ne 1 -or $headingTrigger.GetAttribute('isActive') -cne 'yes') {
    throw 'Expected one active Room heading trigger in System/Autobasher.'
}
$headingFixtures = @(
    ,@('Ant colony. 14625 (Inside).','Ant colony','14625')
    ,@('Ant colony. 14625 (Inside)','Ant colony','14625')
    ,@('Ant colony. 14625.','Ant colony','14625')
    ,@('Ant colony. 14625','Ant colony','14625')
    ,@("A warrior's retreat. 42 (Outside).","A warrior's retreat",'42')
    ,@('A room, with punctuation!. 17.','A room, with punctuation!','17')
)
foreach ($fixture in $headingFixtures) {
    if ($fixture[0] -cnotmatch $headingPatterns[0].InnerText -or $Matches[1] -cne $fixture[1] -or $Matches[2] -cne $fixture[2]) {
        throw ('Room heading trigger rejects or miscaptures: ' + $fixture[0])
    }
}
foreach ($headingLine in @('. 42.','Ant colony 42.','Ant colony. -42.','Ant colony. abc.','Ant colony. 42 (Inside','Ant colony. 42 (Inside). extra','Ant colony. 42 extra','Ant colony. 42..')) {
    if ($headingLine -cmatch $headingPatterns[0].InnerText) { throw ('Room heading trigger incorrectly accepts: ' + $headingLine) }
}
# Zero is syntactically numeric; onHeading must require a positive room ID and
# validate the captured name/ID against fresh GMCP in the current walk frame.
$slain = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Autobasher"]/Trigger[name="Denizen slain"]')
if (!$slain -or $slain.script -cne 'dem.hunt.onKill(matches[2])' -or $slain.SelectSingleNode('regexCodeList/string').InnerText -cne '^The final blow is too much, you have slain (.+)\.$') {
    throw 'Denizen slain trigger contract changed.'
}
$missingNodes = @($package.SelectNodes('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Autobasher"]/Trigger[name="Target absent"]'))
if ($missingNodes.Count -ne 1) { throw 'Target absent trigger is missing or duplicated.' }
$missingTrigger = $missingNodes[0]
$missingPatterns = @($missingTrigger.SelectNodes('regexCodeList/string'))
if ($missingPatterns.Count -ne 1) { throw 'Target absent must contain exactly one regex.' }
$missingLines = @(
    'You do not see that individual here.'
    'Nothing can be seen here by that name.'
    'Ahh, I am truly sorry, but I do not see anyone by that name here.'
    'You detect nothing here by that name.'
)
foreach ($line in $missingLines) {
    if ($line -cnotmatch $missingPatterns[0].InnerText) { throw ('Target absent trigger rejects: ' + $line) }
    foreach ($invalid in @(($line + ' extra'), ('prefix ' + $line), $line.Replace('.','!'))) {
        if ($invalid -cmatch $missingPatterns[0].InnerText) { throw ('Target absent trigger incorrectly accepts: ' + $invalid) }
    }
}
$unavailableTriggers = @{}
foreach ($kind in @('bal','eq')) {
    $resource = if ($kind -ceq 'bal') { 'balance' } else { 'equilibrium' }
    $name = if ($kind -ceq 'bal') { 'Balance unavailable' } else { 'Equilibrium unavailable' }
    $nodes = @($package.SelectNodes(('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Balances"]/Trigger[name="{0}"]' -f $name)))
    if ($nodes.Count -ne 1) { throw ($name + ' trigger is missing or duplicated.') }
    $trigger = $nodes[0]
    $patterns = @($trigger.SelectNodes('regexCodeList/string'))
    $types = @($trigger.SelectNodes('regexCodePropertyList/integer'))
    $pattern = '^You must regain (?:your )?' + $resource + ' first\.$'
    $script = 'dem.onBalanceUnavailable("' + $kind + '")'
    if ($patterns.Count -ne 1 -or $patterns[0].InnerText -cne $pattern -or $types.Count -ne 1 -or $types[0].InnerText -cne '1' -or $trigger.script -cne $script) {
        throw ($name + ' must use the exact approved regex, type, and script.')
    }
    if ($package.SelectNodes(('//Trigger[@isActive="yes" and name="{0}"]' -f $name)).Count -ne 1 -or $trigger.GetAttribute('isActive') -cne 'yes') {
        throw ('Expected one active ' + $name + ' trigger in System/Balances.')
    }
    foreach ($text in @(('You must regain ' + $resource + ' first.'), ('You must regain your ' + $resource + ' first.'))) {
        if ($text -cnotmatch $pattern) { throw ($name + ' trigger rejects: ' + $text) }
        foreach ($invalid in @(('prefix ' + $text), ($text + ' extra'), $text.Replace('.','!'))) {
            if ($invalid -cmatch $pattern) { throw ($name + ' trigger incorrectly accepts: ' + $invalid) }
        }
    }
    $unavailableTriggers[$kind] = $trigger
}
$graceNodes = @($package.SelectNodes('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Autobasher"]/Trigger[name="Grace blocks attack"]'))
if ($graceNodes.Count -ne 1) { throw 'Grace blocks attack trigger is missing or duplicated.' }
$graceTrigger = $graceNodes[0]
$gracePatterns = @($graceTrigger.SelectNodes('regexCodeList/string'))
$graceTypes = @($graceTrigger.SelectNodes('regexCodePropertyList/integer'))
if ($gracePatterns.Count -ne 1 -or $gracePatterns[0].InnerText -cne '^You currently walk in divine grace\b' -or $graceTypes.Count -ne 1 -or $graceTypes[0].InnerText -cne '1' -or $graceTrigger.script -cne 'dem.hunt.onAttackRejected("Divine grace prevents attacks; renounce grace manually before enabling Hunt.")') {
    throw 'Grace blocks attack must use the exact approved regex, type, and script.'
}
if ($package.SelectNodes('//Trigger[@isActive="yes" and name="Grace blocks attack"]').Count -ne 1 -or $graceTrigger.GetAttribute('isActive') -cne 'yes') {
    throw 'Expected one active Grace blocks attack trigger in System/Autobasher.'
}
$graceLine = 'You currently walk in divine grace and may neither be harmed nor harm another.'
if ($graceLine -cnotmatch $gracePatterns[0].InnerText) { throw 'Grace blocks attack rejects the actual complete game line.' }
foreach ($text in @(('prefix ' + $graceLine), ('[Notice] ' + $graceLine), ' You currently walk in divine grace.', 'you currently walk in divine grace.', 'You currently walk in divine graceful harmony.', 'You walk north.', 'You must regain balance first.')) {
    if ($text -cmatch $gracePatterns[0].InnerText) { throw ('Grace blocks attack incorrectly accepts: ' + $text) }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('demonic-tests-' + [guid]::NewGuid().ToString('N') + '.lua')
try {
    $chunks = [Collections.Generic.List[string]]::new()
    $chunks.Add('function DEMONIC_TEST_LOAD()')
    foreach ($script in $scripts) {
        $label = $script.ParentNode.name
        $chunks.Add(('assert((loadstring or load)([====[{0}]====], {1}))()' -f $script.InnerText, ('"' + $label + '"')))
    }
    $chunks.Add('end')
    $chunks.Add('function DEMONIC_TEST_TARGET_ALIAS(ref)')
    $chunks.Add('matches = {"t " .. ref, ref}')
    $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "Targeting alias"))()' -f $targetAlias.script))
    $chunks.Add('end')
    $chunks.Add('function DEMONIC_TEST_ENTERED(direction)')
    $chunks.Add('matches = {"You walk " .. direction .. ".", direction}')
    $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "Room entered trigger"))()' -f $enteredTrigger.script))
    $chunks.Add('end')
    $chunks.Add('function DEMONIC_TEST_HEADING(name, id)')
    $chunks.Add('line = name .. ". " .. tostring(id) .. "."; matches = {line, name, tostring(id)}')
    $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "Room heading trigger"))()' -f $headingTrigger.script))
    $chunks.Add('end')
    $chunks.Add('function DEMONIC_TEST_HUNT_STATUS(detailed)')
    $chunks.Add('matches = {detailed and "hunt status debug" or "hunt status", detailed and "debug" or nil}')
    $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "Hunt status alias"))()' -f $statusAlias.script))
    $chunks.Add('end')
    $chunks.Add('local missingTargetLines = {}')
    foreach ($line in $missingLines) { $chunks.Add(('missingTargetLines[ [====[{0}]====] ] = true' -f $line)) }
    $chunks.Add('function DEMONIC_TEST_MISSING_TARGET(text)')
    $chunks.Add('assert(missingTargetLines[text], "Unvalidated Target absent fixture")')
    $chunks.Add('line = text; matches = {text}')
    $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "Target absent trigger"))()' -f $missingTrigger.script))
    $chunks.Add('end')
    $chunks.Add('function DEMONIC_TEST_UNAVAILABLE(kind)')
    $chunks.Add('assert(kind == "bal" or kind == "eq", "Unknown unavailable resource")')
    foreach ($kind in @('bal','eq')) {
        $resource = if ($kind -ceq 'bal') { 'balance' } else { 'equilibrium' }
        $chunks.Add(('if kind == "{0}" then' -f $kind))
        $chunks.Add(('line = "You must regain {0} first."; matches = {{line}}' -f $resource))
        $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "{1} unavailable trigger"))()' -f $unavailableTriggers[$kind].script, $resource))
        $chunks.Add('end')
    }
    $chunks.Add('end')
    $chunks.Add('function DEMONIC_TEST_GRACE()')
    $chunks.Add(('line = [====[{0}]====]; matches = {{line}}' -f $graceLine))
    $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "Grace blocks attack trigger"))()' -f $graceTrigger.script))
    $chunks.Add('end')
    $testFile = (Join-Path $PSScriptRoot 'run.lua').Replace('\','/')
    $chunks.Add(('dofile("{0}")' -f $testFile))
    [IO.File]::WriteAllText($temp, ($chunks -join "`n"), [Text.UTF8Encoding]::new($false))
    & lua $temp
    if ($LASTEXITCODE -ne 0) { throw 'Demonic behavioral tests failed.' }
    foreach ($node in $package.SelectNodes('//script[string-length(text()) > 0]')) {
        [IO.File]::WriteAllText($temp, $node.InnerText, [Text.UTF8Encoding]::new($false))
        & luac -p $temp
        if ($LASTEXITCODE -ne 0) { throw ('Lua syntax error: ' + $node.ParentNode.name) }
    }
    & luac -p (Join-Path $root 'Demonic/config.lua')
    if ($LASTEXITCODE -ne 0) { throw 'Lua syntax error: Demonic/config.lua' }
    $hunt = $package.SelectSingleNode('//AliasPackage/AliasGroup[name="System"]/AliasGroup[name="Autobasher"]/Alias[name="Hunt mode"]')
    if (!$hunt -or $hunt.regex -ne '^hunt$') { throw 'Hunt mode alias is missing or misplaced.' }
    $balanceFolder = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Balances"]')
    if (@($balanceFolder.SelectNodes('Trigger')).Count -lt 5) { throw 'System balance triggers are missing.' }
    Write-Output 'XML structure, source synchronization, alias/trigger contracts, and all Lua syntax: PASS'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
}
