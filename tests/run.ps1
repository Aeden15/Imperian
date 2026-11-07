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
$temp = Join-Path ([IO.Path]::GetTempPath()) ('demonic-tests-' + [guid]::NewGuid().ToString('N') + '.lua')
try {
    $chunks = [Collections.Generic.List[string]]::new()
    $chunks.Add('function DEMONIC_TEST_LOAD()')
    foreach ($script in $scripts) {
        $label = $script.ParentNode.name
        $chunks.Add(('assert((loadstring or load)([====[{0}]====], {1}))()' -f $script.InnerText, ('"' + $label + '"')))
    }
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
    $hunt = $package.SelectSingleNode('//AliasPackage/AliasGroup[name="Demonic"]/AliasGroup[name="System"]/AliasGroup[name="Autobasher"]/Alias[name="Hunt mode"]')
    if (!$hunt -or $hunt.regex -ne '^hunt$') { throw 'Hunt mode alias is missing or misplaced.' }
    $balanceFolder = $package.SelectSingleNode('//TriggerPackage/TriggerGroup[name="Demonic"]/TriggerGroup[name="System"]/TriggerGroup[name="Balances"]')
    if (@($balanceFolder.SelectNodes('Trigger')).Count -lt 5) { throw 'System balance triggers are missing.' }
    Write-Output 'XML structure and all embedded Lua syntax: PASS'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
}
