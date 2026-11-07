# Bundle readable Lua into the existing Mudlet package. No external runtime files.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$xmlPath = Join-Path $root 'Demonic/Demonic.xml'
[xml]$doc = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Demonic.template.xml') -Raw

function Set-Text($node, [string]$name, [string]$value) {
    $child = $node.SelectSingleNode($name)
    if (!$child) { $child = $doc.CreateElement($name); [void]$node.AppendChild($child) }
    $child.InnerText = $value
}
function Get-Group([string]$path) {
    $node = $doc.SelectSingleNode($path)
    if (!$node) { throw "Missing package folder: $path" }
    return $node
}
function Remove-Owned($parent, [string]$tag, [string]$name) {
    foreach ($node in @($parent.SelectNodes($tag))) {
        if ($node.name -eq $name) { [void]$parent.RemoveChild($node) }
    }
}
function Add-Script($parent, [string]$name, [string]$source, [bool]$first = $false) {
    Remove-Owned $parent 'Script' $name
    $node = $doc.CreateElement('Script')
    $node.SetAttribute('isActive','yes'); $node.SetAttribute('isFolder','no')
    Set-Text $node 'name' $name
    Set-Text $node 'packageName' ''
    Set-Text $node 'script' (Get-Content -LiteralPath (Join-Path $root "Demonic/src/$source.lua") -Raw)
    [void]$node.AppendChild($doc.CreateElement('eventHandlerList'))
    $anchor = $parent.SelectSingleNode('Script | ScriptGroup')
    if ($first -and $anchor) { [void]$parent.InsertBefore($node, $anchor) }
    else { [void]$parent.AppendChild($node) }
}
function Add-Alias($parent, [string]$name, [string]$pattern, [string]$script) {
    Remove-Owned $parent 'Alias' $name
    $node = $doc.CreateElement('Alias')
    $node.SetAttribute('isActive','yes'); $node.SetAttribute('isFolder','no')
    Set-Text $node 'name' $name
    Set-Text $node 'script' $script
    Set-Text $node 'command' ''
    Set-Text $node 'packageName' ''
    Set-Text $node 'regex' $pattern
    [void]$parent.AppendChild($node)
}
function Add-Trigger($parent, [string]$name, [string]$pattern, [string]$script, [int]$type = 1) {
    Remove-Owned $parent 'Trigger' $name
    $node = $doc.CreateElement('Trigger')
    foreach ($attr in $parent.Attributes) { $node.SetAttribute($attr.Name,$attr.Value) }
    $node.SetAttribute('isFolder','no')
    foreach ($child in $parent.ChildNodes) {
        # PowerShell's XML adapter makes .Name return a nested <name> value.
        # LocalName is the actual element tag, including for existing triggers.
        if ($child.NodeType -eq 'Element' -and $child.LocalName -notin @('Trigger','TriggerGroup')) {
            [void]$node.AppendChild($child.CloneNode($true))
        }
    }
    Set-Text $node 'name' $name
    Set-Text $node 'script' $script
    $patterns = $node.SelectSingleNode('regexCodeList'); $patterns.RemoveAll()
    $entry = $doc.CreateElement('string'); $entry.InnerText = $pattern; [void]$patterns.AppendChild($entry)
    $types = $node.SelectSingleNode('regexCodePropertyList'); $types.RemoveAll()
    $entry = $doc.CreateElement('integer'); $entry.InnerText = [string]$type; [void]$types.AppendChild($entry)
    [void]$parent.AppendChild($node)
}

$scriptRoot = Get-Group '//ScriptPackage/ScriptGroup[name="Demonic"]'
$system = Get-Group '//ScriptPackage/ScriptGroup[name="Demonic"]/ScriptGroup[name="System"]'
# Add in reverse order because these shared scripts must precede child folders.
Add-Script $system 'Balances and Vitals' 'balances' $true
Add-Script $system 'Targeting' 'targeting' $true
Add-Script $system 'Core' 'core' $true
Add-Script (Get-Group '//ScriptPackage//ScriptGroup[name="Api stuff"]') 'Room Tracking' 'room'
Add-Script (Get-Group '//ScriptPackage//ScriptGroup[name="Autobasher"]') 'Hunt Controller' 'hunt'
Add-Script (Get-Group '//ScriptPackage//ScriptGroup[name="Ritualism"]') 'Ritualism Commands' 'ritualism'
Add-Script $scriptRoot 'Initialize Demonic' 'bootstrap'

$aliases = Get-Group '//AliasPackage/AliasGroup[name="Demonic"]/AliasGroup[name="System"]'
$targetAliases = $aliases.SelectSingleNode('AliasGroup[name="Targeting"]')
if (!$targetAliases) {
    $targetAliases = $doc.CreateElement('AliasGroup')
    $targetAliases.SetAttribute('isActive','yes'); $targetAliases.SetAttribute('isFolder','yes')
    foreach ($name in @('name','script','command','packageName','regex')) { Set-Text $targetAliases $name '' }
    Set-Text $targetAliases 'name' 'Targeting'
    [void]$aliases.AppendChild($targetAliases)
}
Add-Alias $targetAliases 'Target player' '^t player (\S+)$' 'dem.targeting.setPlayer(matches[2])'
Add-Alias $targetAliases 'Target denizen' '^t denizen (\S+)$' 'dem.targeting.setDenizen(matches[2])'
Add-Alias $targetAliases 'Clear target' '^t clear$' 'dem.targeting.clear()'
$huntAliases = Get-Group '//AliasPackage/AliasGroup[name="Demonic"]/AliasGroup[name="System"]/AliasGroup[name="Autobasher"]'
Add-Alias $huntAliases 'Hunt mode' '^hunt$' 'dem.hunt.toggle()'
Add-Alias $huntAliases 'Hunt add' '^hunt add (.+)$' 'dem.hunt.add(matches[2])'
Add-Alias $huntAliases 'Hunt remove' '^hunt remove (.+)$' 'dem.hunt.remove(matches[2])'
Add-Alias $huntAliases 'Hunt list' '^hunt list$' 'dem.hunt.list()'
Add-Alias $huntAliases 'Hunt status' '^hunt status$' 'dem.hunt.status()'
Add-Alias $huntAliases 'Hunt limits' '^hunt limits (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)$' 'dem.hunt.setLimits(tonumber(matches[2]), tonumber(matches[3]))'

$balances = Get-Group '//TriggerPackage/TriggerGroup[name="Demonic"]/TriggerGroup[name="System"]/TriggerGroup[name="Balances"]'
Add-Trigger $balances 'Balance loss duration' '^Balance Taken:\s*(\d+(?:\.\d+)?)s\s*$' 'dem.balances.taken("bal", tonumber(matches[2]))'
Add-Trigger $balances 'Equilibrium loss duration' '^Equilibrium Taken:\s*(\d+(?:\.\d+)?)s\s*$' 'dem.balances.taken("eq", tonumber(matches[2]))'
Add-Trigger $balances 'Balance regained' '^You have recovered balance\.$' 'dem.balances.recovered("bal")'
Add-Trigger $balances 'Equilibrium regained' '^You have (?:regained your mental equilibrium|recovered equilibrium)\.$' 'dem.balances.recovered("eq")'
Add-Trigger $balances 'Balance unavailable' '^You must regain (?:your )?balance first\.$' 'dem.balances.taken("bal")'
Add-Trigger $balances 'Equilibrium unavailable' '^You must regain (?:your )?equilibrium first\.$' 'dem.balances.taken("eq")'
Add-Trigger $balances 'Prompt readiness' '' 'dem.onPrompt(line)' 7
$hunting = Get-Group '//TriggerPackage/TriggerGroup[name="Demonic"]/TriggerGroup[name="System"]/TriggerGroup[name="Autobasher"]'
Add-Trigger $hunting 'Denizen slain' '^The final blow is too much, you have slain (.+)\.$' 'dem.hunt.onKill(matches[2])'
Add-Trigger $hunting 'Target absent' '^You do not see that individual here\.$' 'dem.hunt.onMissing()'

$settings = [Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.IndentChars = "`t"
$settings.NewLineChars = "`n"
$settings.NewLineHandling = 'None'
$settings.Encoding = [Text.UTF8Encoding]::new($false)
if ($doc.SelectNodes('//Trigger/Trigger | //Trigger/TriggerGroup').Count -ne 0) {
    throw 'Generated triggers must not contain other triggers.'
}
# Build in memory before replacing the output: failed builds leave it intact.
$memory = [IO.MemoryStream]::new()
$writer = [Xml.XmlWriter]::Create($memory,$settings)
try {
    $doc.Save($writer)
    $writer.Flush()
    $content = $memory.ToArray()
} finally { $writer.Dispose(); $memory.Dispose() }
if ($content.Length -gt 1048576) { throw 'Unexpectedly large generated package.' }
[IO.File]::WriteAllBytes($xmlPath, $content)
Write-Output 'Bundled Demonic/Demonic.xml'
