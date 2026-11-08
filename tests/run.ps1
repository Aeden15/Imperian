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
    'Room GUI' = 'ui'
    'Ritualism Commands' = 'ritualism'; 'Initialize Demonic' = 'bootstrap'
    'Malignosis Commands' = 'malignosis'; 'Diabolist defences' = 'defences'; 'Nightfall Commands' = 'nightfall'
}
if ($scripts.Count -ne $sourceFiles.Count) { throw 'Unexpected embedded Script count.' }
# The export is flat: Package Manager supplies the single Demonic wrapper.
# Compare the entire non-owned skeleton, including group attributes/metadata,
# rather than merely accepting folder paths that happen to contain our leaves.
$preserved = $package.Clone()
$owned = @{
    Script = @($sourceFiles.Keys)
    Alias = @('Hunt mode','Hunt add','Hunt remove','Hunt list','Hunt status','Hunt limits','Targeting','Show room GUI','Hide room GUI','Reset room GUI','Defs')
    Trigger = @('Balance loss duration','Equilibrium loss duration','Balance regained','Equilibrium regained','Balance unavailable','Equilibrium unavailable','Prompt readiness','Denizen slain','Target absent','Grace blocks attack','Vitality activated','Demon regeneration','Demon armor','Missing ouroboros','Summoned ouroboros','Soulmask','Syphon ceased','Syphoning on','Nightfall defence','Nightfall cease','Vitality consumed','Vitality cooldown','Vitality ready','Wraith materialised','Wraith charges','Wraith lost charges','Wraith vanished','Wraith status header','Wraith status row')
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
if ($config -cnotmatch '(?m)^created = "2026-11-07T16:29:35-06:00"\r?$') { throw 'Export creation timestamp was not preserved.' }
if ($config -cnotmatch '(?m)^mpackage = \[\[Demonic\]\]\r?$' -or $config -cnotmatch '(?m)^version = \[\[0\.1\.12\]\]\r?$' -or $config -cnotmatch '(?s)description = \[\[Shared targeting.+?\]\]') {
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
$guiContracts = @{
    show = @('Show room GUI', '^demui show$', 'dem.ui.show()')
    hide = @('Hide room GUI', '^demui hide$', 'dem.ui.hide()')
    reset = @('Reset room GUI', '^demui reset$', 'dem.ui.resetLayout()')
}
$guiFolder = $package.SelectSingleNode('//AliasPackage/AliasGroup[name="System"]/AliasGroup[name="GUI"]')
if (!$guiFolder -or $guiFolder.SelectNodes('Alias').Count -ne 3) { throw 'GUI controls are missing or duplicated.' }
foreach ($command in $guiContracts.Keys) {
    $contract = $guiContracts[$command]
    $nodes = @($guiFolder.SelectNodes(('Alias[name="{0}"]' -f $contract[0])))
    if ($nodes.Count -ne 1 -or $nodes[0].regex -cne $contract[1] -or $nodes[0].script -cne $contract[2]) {
        throw ('GUI alias contract failed: ' + $command)
    }
}
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
# Reported GMCP identity is the only room boundary; native walk/heading
# text must not install active or inactive generated synchronization triggers.
if ($package.SelectNodes('//Trigger[name="Room entered" or name="Room heading"]').Count -ne 0) {
    throw 'Generated movement/heading triggers must be absent.'
}
foreach ($script in $scripts) {
    if ($script.InnerText -cmatch 'sysDataSendRequest') {
        throw 'Outgoing movement interception must not be registered.'
    }
}
$slainNodes = @($package.SelectNodes('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Autobasher"]/Trigger[name="Denizen slain"]'))
if ($slainNodes.Count -ne 1) { throw 'Denizen slain trigger is missing or duplicated.' }
$slain = $slainNodes[0]
$slainPatterns = @($slain.SelectNodes('regexCodeList/string'))
$slainTypes = @($slain.SelectNodes('regexCodePropertyList/integer'))
if ($slain.script -cne 'dem.hunt.onKill(matches[2])' -or $slainPatterns.Count -ne 1 -or $slainPatterns[0].InnerText -cne '^The final blow is too much, you have slain (.+)\.$' -or $slainTypes.Count -ne 1 -or $slainTypes[0].InnerText -cne '1') {
    throw 'Denizen slain trigger contract changed.'
}
if ($slain.GetAttribute('isActive') -cne 'yes' -or $package.SelectNodes('//Trigger[@isActive="yes" and name="Denizen slain"]').Count -ne 1) {
    throw 'Expected one active Denizen slain trigger in System/Autobasher.'
}
foreach ($name in @('a warrior ant', "a warrior's pet", 'Fido')) {
    $text = 'The final blow is too much, you have slain ' + $name + '.'
    if ($text -cnotmatch $slainPatterns[0].InnerText -or $Matches[1] -cne $name) { throw ('Denizen slain miscaptures: ' + $text) }
    foreach ($invalid in @(('prefix ' + $text), ($text + ' extra'), $text.Replace('.','!'))) {
        if ($invalid -cmatch $slainPatterns[0].InnerText) { throw ('Denizen slain incorrectly accepts: ' + $invalid) }
    }
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
    $defsAlias = $package.SelectSingleNode('//AliasPackage//Alias[name="Defs"]')
    $huntAlias = $package.SelectSingleNode('//AliasPackage//Alias[name="Hunt mode"]')
    $prompt = $package.SelectSingleNode('//TriggerPackage//Trigger[name="Prompt readiness"]')
    foreach ($entry in @(@('DEMONIC_TEST_DEFS_ALIAS',$defsAlias), @('DEMONIC_TEST_HUNT_ALIAS',$huntAlias), @('DEMONIC_TEST_PROMPT',$prompt))) {
        if (!$entry[1]) { throw ('Missing entry for ' + $entry[0]) }
        $chunks.Add(('function {0}() line=""; matches={{}}; return assert((loadstring or load)([====[{1}]====],"actual alias/trigger"))() end' -f $entry[0],$entry[1].script))
    }
    $chunks.Add('function DEMONIC_TEST_CLASS_TRIGGER(name, text, ...) line=text or ""; matches={line,...}')
    foreach ($node in $package.SelectNodes('//TriggerPackage/TriggerGroup[name="Diabolist"]//Trigger')) {
        $chunks.Add(('if name == [====[{0}]====] then return assert((loadstring or load)([====[{1}]====],"class trigger"))() end' -f $node.name,$node.script))
    }
    $chunks.Add('error("Unknown class trigger: " .. tostring(name)) end')
    # Match the supplied log with the generated regexes, then execute their actual
    # Lua bodies and captures. Only Mudlet's native regex engine is substituted.
    $chunks.Add('function DEMONIC_TEST_WRAITH_LOG()')
    $wraithFolder = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="Diabolist"]/TriggerGroup[name="Nightfall"]/TriggerGroup[name="Wraiths"]')
    foreach ($text in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/wraith-events.txt')) {
        foreach ($trigger in $wraithFolder.SelectNodes('Trigger')) {
            $hit = [regex]::Match($text, $trigger.regexCodeList.string)
            if (!$hit.Success) { continue }
            $captures = @($hit.Groups | ForEach-Object { '[====[' + $_.Value + ']====]' }) -join ','
            $chunks.Add(('line=[====[{0}]====]; matches={{{1}}}; assert((loadstring or load)([====[{2}]====],"log trigger"))()' -f $text,$captures,$trigger.script))
        }
    }
    $chunks.Add('end')
    $chunks.Add('function DEMONIC_TEST_GUI_ALIAS(command)')
    foreach ($command in $guiContracts.Keys) {
        $node = $guiFolder.SelectSingleNode(('Alias[name="{0}"]' -f $guiContracts[$command][0]))
        $chunks.Add(('if command == "{0}" then return assert((loadstring or load)([====[{1}]====], "GUI alias"))() end' -f $command, $node.script))
    }
    $chunks.Add('error("Unknown GUI command") end')
    $chunks.Add('function DEMONIC_TEST_TARGET_ALIAS(ref)')
    $chunks.Add('matches = {"t " .. ref, ref}')
    $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "Targeting alias"))()' -f $targetAlias.script))
    $chunks.Add('end')
    $chunks.Add('function DEMONIC_TEST_KILL(name)')
    $chunks.Add('line = "The final blow is too much, you have slain " .. name .. "."; matches = {line, name}')
    $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "Denizen slain trigger"))()' -f $slain.script))
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
    $guiTests = (Join-Path $PSScriptRoot 'gui.lua').Replace('\','/')
    $chunks.Add(('dofile("{0}")' -f $guiTests))
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
    & (Join-Path $PSScriptRoot 'check-export.ps1')
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
}
