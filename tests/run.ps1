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
if ($package.SelectNodes('//Trigger/Trigger | //Trigger/TriggerGroup').Count -ne 0) { throw 'Nested generated triggers.' }
$scripts = @($package.SelectNodes('//ScriptPackage//Script/script'))
$sourceFiles = @{
    'Core' = 'core'; 'Targeting' = 'targeting'; 'Balances and Vitals' = 'balances'
    'Room Tracking' = 'room'; 'Hunt Controller' = 'hunt'
    'Ritualism Commands' = 'ritualism'; 'Initialize Demonic' = 'bootstrap'
}
if ($scripts.Count -ne $sourceFiles.Count) { throw 'Unexpected embedded Script count.' }
foreach ($name in $sourceFiles.Keys) {
    $nodes = @($package.SelectNodes(('//ScriptPackage//Script[name="{0}"]/script' -f $name)))
    $source = Get-Content -LiteralPath (Join-Path $root ('Demonic/src/{0}.lua' -f $sourceFiles[$name])) -Raw
    if ($nodes.Count -ne 1 -or $nodes[0].InnerText -cne $source) {
        throw ('Embedded Script does not match its source: ' + $name)
    }
}
$targetFolder = $package.SelectSingleNode('//AliasPackage/AliasGroup[name="Demonic"]/AliasGroup[name="System"]/AliasGroup[name="Targeting"]')
if (!$targetFolder) { throw 'Targeting alias folder is missing.' }
$targetNodes = @($targetFolder.SelectNodes('.//Alias'))
if ($targetNodes.Count -ne 1) { throw 'Targeting must contain exactly one alias.' }
$targetAlias = $targetNodes[0]
if ($targetAlias.name -cne 'Targeting' -or $targetAlias.regex -cne '^t (\w+)$' -or $targetAlias.script -cne 'dem.targeting.set(matches[2])') {
    throw 'Targeting alias must use the exact approved name, regex, and script.'
}
if ($package.SelectNodes('//Alias[name="Target player" or name="Target denizen" or name="Clear target"]').Count -ne 0) {
    throw 'Legacy targeting aliases remain in the package.'
}
foreach ($command in @('t ant','t ant427409','t 427409','t clear')) {
    if ($command -cnotmatch $targetAlias.regex) { throw ('Targeting alias rejects: ' + $command) }
}
foreach ($command in @('t player Name','t denizen ant','t ant extra',' t ant','t  ant','t ant ')) {
    if ($command -cmatch $targetAlias.regex) { throw ('Targeting alias incorrectly accepts: ' + $command) }
}
$missingNodes = @($package.SelectNodes('//TriggerPackage/TriggerGroup[name="Demonic"]/TriggerGroup[name="System"]/TriggerGroup[name="Autobasher"]/Trigger[name="Target absent"]'))
if ($missingNodes.Count -ne 1) { throw 'Target absent trigger is missing or duplicated.' }
$missingTrigger = $missingNodes[0]
$missingPatterns = @($missingTrigger.SelectNodes('regexCodeList/string'))
if ($missingPatterns.Count -ne 1) { throw 'Target absent must contain exactly one regex.' }
$missingLines = @(
    'You do not see that individual here.'
    'Nothing can be seen here by that name.'
    'Ahh, I am truly sorry, but I do not see anyone by that name here.'
)
foreach ($line in $missingLines) {
    if ($line -cnotmatch $missingPatterns[0].InnerText) { throw ('Target absent trigger rejects: ' + $line) }
    foreach ($invalid in @(($line + ' extra'), ('prefix ' + $line), $line.Replace('.','!'))) {
        if ($invalid -cmatch $missingPatterns[0].InnerText) { throw ('Target absent trigger incorrectly accepts: ' + $invalid) }
    }
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
    $chunks.Add('local missingTargetLines = {}')
    foreach ($line in $missingLines) { $chunks.Add(('missingTargetLines[ [====[{0}]====] ] = true' -f $line)) }
    $chunks.Add('function DEMONIC_TEST_MISSING_TARGET(text)')
    $chunks.Add('assert(missingTargetLines[text], "Unvalidated Target absent fixture")')
    $chunks.Add('line = text; matches = {text}')
    $chunks.Add(('return assert((loadstring or load)([====[{0}]====], "Target absent trigger"))()' -f $missingTrigger.script))
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
    $hunt = $package.SelectSingleNode('//AliasPackage/AliasGroup[name="Demonic"]/AliasGroup[name="System"]/AliasGroup[name="Autobasher"]/Alias[name="Hunt mode"]')
    if (!$hunt -or $hunt.regex -ne '^hunt$') { throw 'Hunt mode alias is missing or misplaced.' }
    $balanceFolder = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="Demonic"]/TriggerGroup[name="System"]/TriggerGroup[name="Balances"]')
    if (@($balanceFolder.SelectNodes('Trigger')).Count -lt 5) { throw 'System balance triggers are missing.' }
    Write-Output 'XML structure, source synchronization, alias/trigger contracts, and all Lua syntax: PASS'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
}
