# Windows Nextshot flag tool. Mirrors scripts/nextshot-flags.sh.
# Usage: nextshot-flags.ps1 list | set <flag> <off|on> | reset <flag>
# The settings file is %LOCALAPPDATA%\NextshotSettings\settings.json.
# The FLAGS line must match Windows/src/Nextshot.Core/Settings/FeatureFlags.cs.
# A test (FlagTests.ScriptFlagListMatchesRegistry) fails when they differ.
param(
    [Parameter(Position = 0)][string]$Command = 'list',
    [Parameter(Position = 1)][string]$Flag,
    [Parameter(Position = 2)][string]$State,
    [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'NextshotSettings\settings.json')
)

$FLAGS = "zipHandoff:off,on supportSubmission:off,on sessionTitle:off,on updateReminder:off,on screenshotCopy:off,on diagnostics:off,on standaloneCapture:off,on recordingTools:off,on translationTools:off,on cloudShare:off,on automationURLs:off,on automaticUpdates:off,on"

$registry = @{}
foreach ($entry in $FLAGS -split ' ') {
    $name, $states = $entry -split ':'
    $registry[$name] = $states -split ','
}

function Read-Settings {
    if (Test-Path $SettingsPath) {
        try { return Get-Content $SettingsPath -Raw | ConvertFrom-Json -AsHashtable } catch { }
    }
    return @{}
}

function Write-Settings($data) {
    $dir = Split-Path $SettingsPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $data | ConvertTo-Json -Depth 5 | Set-Content $SettingsPath
}

switch ($Command) {
    'list' {
        $data = Read-Settings
        $flags = if ($data.ContainsKey('flags')) { $data['flags'] } else { @{} }
        foreach ($name in $registry.Keys | Sort-Object) {
            $value = if ($flags.ContainsKey($name)) { $flags[$name] } else { '(default)' }
            '{0,-20} {1}' -f $name, $value
        }
    }
    'set' {
        if (-not $registry.ContainsKey($Flag)) { Write-Error "Unknown flag: $Flag"; exit 1 }
        if ($registry[$Flag] -notcontains $State) { Write-Error "State must be one of: $($registry[$Flag] -join ', ')"; exit 1 }
        $data = Read-Settings
        if (-not $data.ContainsKey('flags')) { $data['flags'] = @{} }
        $data['flags'][$Flag] = $State
        Write-Settings $data
    }
    'reset' {
        if (-not $registry.ContainsKey($Flag)) { Write-Error "Unknown flag: $Flag"; exit 1 }
        $data = Read-Settings
        if ($data.ContainsKey('flags')) { $data['flags'].Remove($Flag) }
        Write-Settings $data
    }
    default { Write-Error "Usage: nextshot-flags.ps1 list | set <flag> <state> | reset <flag>"; exit 1 }
}
