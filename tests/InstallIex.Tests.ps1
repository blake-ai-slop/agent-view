# The real one-line install path: GitHub serves install.ps1 as UTF-8 bytes, `irm` decodes them (keeping a BOM as
# U+FEFF) and `iex` runs the text. Simulate exactly that in Windows PowerShell 5.1 and pwsh 7 (when present),
# installing from this checkout into temporary LOCALAPPDATA/Startup/user PATH/TEMP folders.
$repo = (Resolve-Path "$PSScriptRoot/..").ProviderPath
# Hidden override so the same cases can be pointed at another bootstrap (e.g. the broken v0.1.0 file).
$bootstrap = if ($env:AGENT_VIEW_TEST_BOOTSTRAP) { $env:AGENT_VIEW_TEST_BOOTSTRAP } else { Join-Path $repo 'install.ps1' }
$winPs = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
$pwsh = if ($pwshCmd) { $pwshCmd.Source } else { $null }

function New-IexTestSandbox([string]$Name) {
    $root = Join-Path $TestDrive $Name
    $box = [pscustomobject]@{ Root=$root; Local=(Join-Path $root 'local'); Startup=(Join-Path $root 'startup'); Temp=(Join-Path $root 'temp'); UserPath=(Join-Path $root 'userpath.txt') }
    foreach ($d in @($box.Local, $box.Startup, $box.Temp)) { [void][IO.Directory]::CreateDirectory($d) }
    [IO.File]::WriteAllText($box.UserPath, 'C:\keep')
    $box
}
# Runs $Exe with $Arguments in an environment pointing at the sandbox; returns exit code and output.
function Invoke-IexTestHost([string]$Exe, [string]$Arguments, $Box, [hashtable]$Extra = @{}) {
    $vars = @{
        LOCALAPPDATA=$Box.Local; AGENT_VIEW_STARTUP_DIR=$Box.Startup; AGENT_VIEW_USER_PATH_FILE=$Box.UserPath; TEMP=$Box.Temp; TMP=$Box.Temp
        AGENT_VIEW_SOURCE=$null; AGENT_VIEW_YES=$null; AGENT_VIEW_NO_START=$null; AGENT_VIEW_NO_AUTOSTART=$null; AGENT_VIEW_WIDGET=$null; AGENT_VIEW_QUIET=$null
        AGENT_VIEW_BOOTSTRAP=$null; AGENT_VIEW_INSTALL_SCRIPT=$null; AV_TEST_BOOTSTRAP=$bootstrap
    }
    foreach ($k in $Extra.Keys) { $vars[$k] = $Extra[$k] }
    $saved = @{}
    try {
        foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process'); [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process') }
        $psi = New-Object Diagnostics.ProcessStartInfo $Exe, $Arguments
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(180000)) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null; throw "timeout: $Exe $Arguments" }
        $p.WaitForExit()
        [pscustomobject]@{ Code=$p.ExitCode; Output=($out.Result + "`n" + $err.Result) }
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
    }
}
function New-IexTestRunner([string]$Mode) {
    # Read the served bytes, decode as UTF-8 keeping U+FEFF (like irm), then run like the README commands.
    $read = '$text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($env:AV_TEST_BOOTSTRAP)); $global:LASTEXITCODE = 99'
    $run = switch ($Mode) {
        'iex' { '$text | iex' }
        'scriptblock' { '& ([scriptblock]::Create($text)) -Yes -NoStart' }
    }
    $path = Join-Path $TestDrive ("runner-$Mode.ps1")
    [IO.File]::WriteAllText($path, ($read + "`r`n" + $run + "`r`n" + 'exit $LASTEXITCODE' + "`r`n"), (New-Object Text.ASCIIEncoding))
    $path
}
function Assert-IexTestInstalled($Box, $Result) {
    $Result.Code | Should Be 0
    $root = Join-Path $Box.Local 'agent-view'
    foreach ($name in @('Tray.ps1','agent-view.ps1','Quota.ps1','Process.ps1','Theme.ps1','Format.ps1','Ring.ps1','Popup.ps1','Widget.ps1','Settings.ps1','Version.ps1','Cli.ps1','uninstall.ps1','launch.vbs','bin\agentview.cmd')) {
        Test-Path -LiteralPath (Join-Path $root $name) | Should Be $true
    }
    Test-Path -LiteralPath (Join-Path $Box.Startup 'agent-view.lnk') | Should Be $true
    [IO.File]::ReadAllText($Box.UserPath) | Should Be ('C:\keep;' + (Join-Path $root 'bin'))
    @(Get-ChildItem -LiteralPath $Box.Temp -Filter 'agent-view-*' -Force).Count | Should Be 0
}

Describe 'install.ps1 bootstrap file' {
    It 'is pure ASCII without a BOM and has no top-level param block' {
        $bytes = [IO.File]::ReadAllBytes($bootstrap)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
        @($bytes | Where-Object { $_ -ge 0x80 }).Count | Should Be 0
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput([Text.Encoding]::UTF8.GetString($bytes), [ref]$tokens, [ref]$errors)
        @($errors).Count | Should Be 0
        ($null -eq $ast.ParamBlock) | Should Be $true
    }
    It 'fetches installer.ps1, which keeps its BOM for Vietnamese text on Windows PowerShell 5.1' {
        $text = [IO.File]::ReadAllText($bootstrap)
        $text | Should Match ([regex]::Escape("'installer.ps1'"))
        $text | Should Match 'WindowsPowerShell\\v1\.0\\powershell\.exe'
        $bytes = [IO.File]::ReadAllBytes((Join-Path $repo 'installer.ps1'))
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $true
    }
}

Describe 'One-line install end to end' {
    $iexRunner = New-IexTestRunner 'iex'
    $sbRunner = New-IexTestRunner 'scriptblock'
    $hosts = @(@{ Name='powershell.exe 5.1'; Exe=$winPs })
    $hosts += @{ Name='pwsh 7'; Exe=$pwsh }

    foreach ($h in $hosts) {
        It "installs via irm | iex in $($h.Name)" -Skip:(-not $h.Exe) {
            $box = New-IexTestSandbox ('iex-' + [guid]::NewGuid().ToString('N'))
            $r = Invoke-IexTestHost $h.Exe ('-NoProfile -ExecutionPolicy Bypass -File "' + $iexRunner + '"') $box @{ AGENT_VIEW_SOURCE=$repo; AGENT_VIEW_YES='1'; AGENT_VIEW_NO_START='1' }
            if ($r.Code -ne 0) { Write-Host $r.Output }
            $r.Output | Should Not Match 'param'
            Assert-IexTestInstalled $box $r
        }
        It "installs via a script block with switches in $($h.Name)" -Skip:(-not $h.Exe) {
            $box = New-IexTestSandbox ('sb-' + [guid]::NewGuid().ToString('N'))
            $r = Invoke-IexTestHost $h.Exe ('-NoProfile -ExecutionPolicy Bypass -File "' + $sbRunner + '"') $box @{ AGENT_VIEW_SOURCE=$repo }
            if ($r.Code -ne 0) { Write-Host $r.Output }
            Assert-IexTestInstalled $box $r
        }
    }
    It 'installs via -File from a checkout, using the installer.ps1 next to it' {
        $box = New-IexTestSandbox ('file-' + [guid]::NewGuid().ToString('N'))
        $r = Invoke-IexTestHost $winPs ('-NoProfile -ExecutionPolicy Bypass -File "' + $bootstrap + '" -Yes -NoStart') $box
        if ($r.Code -ne 0) { Write-Host $r.Output }
        Assert-IexTestInstalled $box $r
    }
    It 'rejects an unknown option before changing anything' {
        $box = New-IexTestSandbox ('bad-' + [guid]::NewGuid().ToString('N'))
        $r = Invoke-IexTestHost $winPs ('-NoProfile -ExecutionPolicy Bypass -File "' + $bootstrap + '" -Bogus') $box @{ AGENT_VIEW_SOURCE=$repo }
        $r.Code | Should Be 2
        $r.Output | Should Match 'unknown option "-Bogus"'
        Test-Path -LiteralPath (Join-Path $box.Local 'agent-view') | Should Be $false
    }
}
