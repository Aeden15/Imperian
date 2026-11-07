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
    Trigger = @('Balance loss duration','Equilibrium loss duration','Balance regained','Equilibrium regained','Balance unavailable','Equilibrium unavailable','Prompt readiness','Denizen slain','Target absent')
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
if ($config -cnotmatch '(?m)^version = \[\[0\.1\.2\]\]\r?$' -or $config -cnotmatch '(?s)description = \[\[Shared targeting.+?\]\]') {
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
    $hunt = $package.SelectSingleNode('//AliasPackage/AliasGroup[name="System"]/AliasGroup[name="Autobasher"]/Alias[name="Hunt mode"]')
    if (!$hunt -or $hunt.regex -ne '^hunt$') { throw 'Hunt mode alias is missing or misplaced.' }
    $balanceFolder = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="System"]/TriggerGroup[name="Balances"]')
    if (@($balanceFolder.SelectNodes('Trigger')).Count -lt 5) { throw 'System balance triggers are missing.' }
    Write-Output 'XML structure, source synchronization, alias/trigger contracts, and all Lua syntax: PASS'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
}
