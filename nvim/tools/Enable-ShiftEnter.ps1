<#
Windows Terminal Shift+Enter -> CSI-u ESC [ 13 ; 2 u.
Preview: .\Enable-ShiftEnter.ps1
Apply:   .\Enable-ShiftEnter.ps1 -Apply
An existing settings file is required; unrelated settings are preserved.
#>
param([string]$SettingsPath, [switch]$Apply)
$ErrorActionPreference = 'Stop'
if (-not $SettingsPath) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    if (@($candidates).Count -ne 1) {
        throw 'Cannot select Windows Terminal settings. Run this script with -SettingsPath <settings.json> -Apply. In Terminal: Settings > Open JSON file.'
    }
    $SettingsPath = @($candidates)[0]
}
$SettingsPath = (Resolve-Path -LiteralPath $SettingsPath).Path
$raw = [IO.File]::ReadAllText($SettingsPath)
# JSONC: preserve quoted strings while removing comments and trailing commas.
$clean = [regex]::Replace($raw, '"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*[\s\S]*?\*/', {
    param($m) if ($m.Value.StartsWith('"')) { $m.Value } else { '' }
})
$clean = [regex]::Replace($clean, '"(?:\\.|[^"\\])*"|,\s*(?=[}\]])', {
    param($m) if ($m.Value.StartsWith('"')) { $m.Value } else { '' }
})
$settings = $clean | ConvertFrom-Json
if ($null -eq $settings -or $settings -is [array]) { throw 'Settings root must be an object.' }
$id = 'User.WordVim.ShiftEnter'
$sequence = [string][char]27 + '[13;2u'
function Remove-ShiftEnterKey($item) {
    if (-not $item.PSObject.Properties['keys']) { return $true }
    $remaining = @($item.keys | Where-Object { ([string]$_).ToLower().Replace(' ','') -notin @('shift+enter','shift+return') })
    if ($remaining.Count -eq @($item.keys).Count) { return $true }
    if ($remaining.Count -eq 0) { $item.PSObject.Properties.Remove('keys'); return $false }
    $item.keys = if ($remaining.Count -eq 1) { $remaining[0] } else { $remaining }
    return $true
}
$actions = @()
foreach ($entry in @($settings.actions)) {
    if ($null -eq $entry -or $entry.id -eq $id) { continue }
    [void](Remove-ShiftEnterKey $entry)
    $actions += $entry
}
$bindings = @()
foreach ($entry in @($settings.keybindings)) {
    if ($null -eq $entry) { continue }
    if (Remove-ShiftEnterKey $entry) { $bindings += $entry }
}
$action = [pscustomobject]@{ id=$id; name='WordVim: Shift+Enter'; command=[pscustomobject]@{action='sendInput';input=$sequence} }
if ($settings.PSObject.Properties['keybindings']) {
    $bindings += [pscustomobject]@{id=$id;keys='shift+enter'}
    $settings.keybindings = @($bindings)
} else {
    $action | Add-Member -NotePropertyName keys -NotePropertyValue 'shift+enter'
}
$actions += $action
if ($settings.PSObject.Properties['actions']) { $settings.actions = @($actions) }
else { $settings | Add-Member -NotePropertyName actions -NotePropertyValue @($actions) }
$result = $settings | ConvertTo-Json -Depth 100
Write-Output "Settings: $SettingsPath"
Write-Output 'Shift+Enter will send ESC [ 13 ; 2 u; ordinary Enter is unchanged.'
Write-Output 'This is a Windows Terminal shortcut and therefore applies to its other applications too.'
if (-not $Apply) { Write-Output 'Preview only. Add -Apply to save (a backup is created).'; exit 0 }
$backup = $SettingsPath + '.wordvim-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID + '.bak'
$temp = $SettingsPath + '.wordvim-' + $PID + '.tmp'
[IO.File]::WriteAllText($temp, $result, (New-Object Text.UTF8Encoding($false)))
# Replace the exact selected file atomically and retain the original as backup.
[IO.File]::Replace($temp, $SettingsPath, $backup)
Write-Output "Saved. Backup: $backup"
Write-Output 'Restart Neovim and use :WordKeyCheck to check Shift+Enter.'
