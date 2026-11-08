# String tables are registered by their owning modules. Loading this file does no IO.
function Register-AgentViewStrings([string]$Module, [hashtable]$Strings) {
    $tables = [AppDomain]::CurrentDomain.GetData('agent-view.strings')
    if ($null -eq $tables) { $tables = @{}; [AppDomain]::CurrentDomain.SetData('agent-view.strings', $tables) }
    $tables[$Module] = $Strings
}
function Get-AgentViewLanguage {
    $language = [AppDomain]::CurrentDomain.GetData('agent-view.language')
    if (-not $language) {
        $language = 'auto'
        try {
            $settingsPath = Join-Path $env:LOCALAPPDATA 'agent-view/settings.json'
            $setting = (Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).Language
            if ($setting -in @('vi','en')) { $language = $setting }
        } catch { }
        [AppDomain]::CurrentDomain.SetData('agent-view.language', $language)
    }
    if ($language -eq 'auto') {
        if ([Globalization.CultureInfo]::CurrentUICulture.Name -match '^vi(?:-|$)') { return 'vi' }
        return 'en'
    }
    return $language
}
# Runtime selection; callers that change preferences save Settings.Language separately.
function Set-AgentViewLanguage([ValidateSet('auto','vi','en')][string]$Language) {
    [AppDomain]::CurrentDomain.SetData('agent-view.language', $Language)
}
function Get-AgentViewText {
    param([string]$Key, [Alias('Args')][object[]]$FormatArgs)
    $parts = $Key -split '\.', 2
    $tables = [AppDomain]::CurrentDomain.GetData('agent-view.strings')
    $value = $null
    if ($parts.Count -eq 2 -and $tables -and $tables.ContainsKey($parts[0])) {
        $module = $tables[$parts[0]]; $language = Get-AgentViewLanguage
        if ($module[$language] -and $module[$language].ContainsKey($parts[1])) { $value = $module[$language][$parts[1]] }
        elseif ($module.en -and $module.en.ContainsKey($parts[1])) { $value = $module.en[$parts[1]] }
    }
    if ($null -eq $value) { return $Key }
    if ($FormatArgs.Count) { try { return ([string]$value -f $FormatArgs) } catch { return [string]$value } }
    return [string]$value
}
Set-Alias -Name T -Value Get-AgentViewText

# Shared console formatting for CLI and installer; neither caller changes localized text.
function Write-AgentViewConsoleStep([string]$Kind, [string]$Text, [string]$Detail) {
    $mark = @{ ok='✓'; fail='✗'; skip='–'; info='·' }[$Kind]
    $color = @{ ok='Green'; fail='Red'; skip='DarkGray'; info='Gray' }[$Kind]
    Write-Host ('  ' + $mark + ' ') -ForegroundColor $color -NoNewline
    Write-Host $Text -NoNewline
    if ($Detail) { Write-Host ('  ' + $Detail) -ForegroundColor DarkGray } else { Write-Host '' }
}
