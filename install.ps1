# agent-view bootstrap installer. Must stay pure ASCII with no BOM and no top-level param():
# `irm .../install.ps1 | iex` hands the text to iex, and a BOM (U+FEFF) breaks a param() block there.
# It fetches installer.ps1 (the real installer, UTF-8 with BOM) into a private temp folder and runs it
# in Windows PowerShell 5.1 with -File, forwarding options and AGENT_VIEW_* environment variables.
# Options: -Yes -NoAutostart -Widget -NoStart -Quiet -Source <url-or-folder>
# (or AGENT_VIEW_YES / _NO_AUTOSTART / _WIDGET / _NO_START / _QUIET = 1, AGENT_VIEW_SOURCE).
$__avCode = & {
    param([object[]]$Argv, [string]$SelfPath)
    $defaultSource = 'https://raw.githubusercontent.com/blake-ai-slop/agent-view/main'
    $flagNames = @('Yes','NoAutostart','Widget','NoStart','Quiet')
    $forward = New-Object 'System.Collections.Generic.List[string]'
    $source = $env:AGENT_VIEW_SOURCE
    $argList = @($Argv)
    for ($i = 0; $i -lt $argList.Count; $i++) {
        $a = [string]$argList[$i]
        $name = $a.TrimStart('-')
        if ($a -match '^-' -and $name -ieq 'Source') {
            if ($i + 1 -ge $argList.Count) { Write-Host '  x agent-view: -Source needs a URL or folder.' -ForegroundColor Red; return 2 }
            $i++; $source = [string]$argList[$i]; continue
        }
        $known = @($flagNames | Where-Object { $a -match '^-' -and $_ -ieq $name })
        if ($known.Count) { $forward.Add('-' + $known[0]); continue }
        Write-Host ('  x agent-view: unknown option "' + $a + '". Use -Yes -NoAutostart -Widget -NoStart -Quiet -Source <url-or-folder>.') -ForegroundColor Red
        return 2
    }
    if ([string]::IsNullOrWhiteSpace($source)) {
        $sibling = $null
        if ($SelfPath) { $sibling = Join-Path (Split-Path -Parent $SelfPath) 'installer.ps1' }
        if ($sibling -and (Test-Path -LiteralPath $sibling -PathType Leaf)) { $source = Split-Path -Parent $SelfPath }
        else { $source = $defaultSource }
    }
    $isLocal = Test-Path -LiteralPath $source -PathType Container
    if ($isLocal) { $source = (Resolve-Path -LiteralPath $source).ProviderPath } else { $source = $source.TrimEnd('/') }

    $temp = Join-Path ([IO.Path]::GetTempPath()) ('agent-view-boot-' + [guid]::NewGuid().ToString('N'))
    $saved = @{}
    try {
        [void][IO.Directory]::CreateDirectory($temp)
        $installer = Join-Path $temp 'installer.ps1'
        if ($isLocal) {
            $from = Join-Path $source 'installer.ps1'
            if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { throw ('installer.ps1 not found in ' + $source) }
            Copy-Item -LiteralPath $from -Destination $installer -Force -ErrorAction Stop
        } else {
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
            $url = $source + '/installer.ps1'
            try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer -ErrorAction Stop }
            catch { throw ('could not download ' + $url + ' - ' + $_.Exception.Message) }
        }

        $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $exe)) { throw ('Windows PowerShell not found: ' + $exe) }
        $interactive = [Environment]::UserInteractive
        try { if ([Console]::IsInputRedirected) { $interactive = $false } } catch { $interactive = $false }
        if (@([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^(?i)-noni' }).Count -gt 0) { $interactive = $false }
        $argText = '-NoProfile -ExecutionPolicy Bypass'
        if (-not $interactive) { $argText += ' -NonInteractive' }
        $argText += ' -File "' + $installer + '"'
        if ($forward.Count) { $argText += ' ' + ($forward -join ' ') }

        # The child inherits this environment: options, test overrides, and where to install from.
        $childEnv = @{ AGENT_VIEW_SOURCE = $source; AGENT_VIEW_BOOTSTRAP = '1'; AGENT_VIEW_INSTALL_SCRIPT = $SelfPath }
        foreach ($k in $childEnv.Keys) {
            $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
            [Environment]::SetEnvironmentVariable($k, $childEnv[$k], 'Process')
        }
        # Shared console (colors, prompts); no redirection. Do not use Start-Process -Wait (waits for grandchildren).
        $psi = New-Object Diagnostics.ProcessStartInfo $exe, $argText
        $psi.UseShellExecute = $false
        $p = [Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        $code = [int]$p.ExitCode
        if ($code -eq 0 -and -not $SelfPath -and $env:LOCALAPPDATA) {
            # One-line install: make `agentview` usable in this session (the installer updated the user PATH).
            $bin = Join-Path $env:LOCALAPPDATA 'agent-view\bin'
            $parts = @(([string]$env:Path).Split(';') | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim().TrimEnd('\') })
            if ((Test-Path -LiteralPath $bin) -and -not ($parts -contains $bin.TrimEnd('\'))) { $env:Path = ([string]$env:Path).TrimEnd(';') + ';' + $bin }
        }
        return $code
    } catch {
        Write-Host ('  x agent-view: install failed - ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host '    Nothing was changed. Check the network and run the install command again.' -ForegroundColor Red
        return 1
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    }
} $args $(if ($MyInvocation.MyCommand.Path -and [IO.Path]::GetFileName($MyInvocation.MyCommand.Path) -ieq 'install.ps1') { $MyInvocation.MyCommand.Path } else { '' })
if ($MyInvocation.MyCommand.Path -and [IO.Path]::GetFileName($MyInvocation.MyCommand.Path) -ieq 'install.ps1') { exit $__avCode }
$global:LASTEXITCODE = $__avCode
Remove-Variable __avCode -ErrorAction SilentlyContinue
