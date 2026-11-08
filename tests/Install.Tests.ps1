. "$PSScriptRoot/../src/Cli.ps1"
. "$PSScriptRoot/../installer.ps1"
. "$PSScriptRoot/../uninstall.ps1"
Set-AgentViewLanguage vi
Describe 'Install and uninstall paths' {
    It 'uses only the supplied application and Startup roots' {
        $paths = Get-AgentViewPaths "$TestDrive/local" "$TestDrive/startup"
        $paths.Root | Should Be (Join-Path "$TestDrive/local" 'agent-view')
        $paths.Shortcut | Should Be (Join-Path "$TestDrive/startup" 'agent-view.lnk')
        $paths.Shim | Should Be (Join-Path $paths.Root 'bin\agentview.cmd')
        $paths.Cli | Should Be (Join-Path $paths.Root 'Cli.ps1')
    }
    It 'honours the hidden Startup override' {
        $old = $env:AGENT_VIEW_STARTUP_DIR
        try { $env:AGENT_VIEW_STARTUP_DIR = "$TestDrive/st"; (Get-AgentViewPaths "$TestDrive/l").Shortcut | Should Be (Join-Path "$TestDrive/st" 'agent-view.lnk') }
        finally { $env:AGENT_VIEW_STARTUP_DIR = $old }
    }
    It 'quotes a launcher path containing spaces and hides its window' {
        $text = Get-AgentViewLaunchScript 'C:\Test Folder\agent-view.ps1'
        $text | Should Match ' -STA -WindowStyle Hidden -File ""C:\\Test Folder\\agent-view.ps1""'
        $text | Should Match ', 0, False$'
    }
    It 'removes application files and shortcut without touching a sibling' {
        $paths = Get-AgentViewPaths "$TestDrive/local" "$TestDrive/startup"
        New-Item -ItemType Directory -Force $paths.Root,"$TestDrive/startup" | Out-Null
        Set-Content (Join-Path $paths.Root 'test.txt') 'test'
        Set-Content $paths.Shortcut 'shortcut'
        Set-Content "$TestDrive/local/keep.txt" 'keep'
        Remove-AgentViewFiles $paths
        Test-Path $paths.Root | Should Be $false
        Test-Path $paths.Shortcut | Should Be $false
        Test-Path "$TestDrive/local/keep.txt" | Should Be $true
    }
    It 'rejects removal of a parent directory' {
        { Remove-AgentViewFiles ([pscustomobject]@{Root="$TestDrive/local";Shortcut="$TestDrive/no.lnk"}) } | Should Throw
    }
}

Describe 'Install options' {
    $none = [pscustomobject]@{ Installed=$false; Autostart=$false; Widget=$false }
    It 'asks only when interactive and no flag or variable is given' {
        (Resolve-AgentViewInstallOptions @{} @{} $true $none).Ask | Should Be $true
        (Resolve-AgentViewInstallOptions @{} @{} $false $none).Ask | Should Be $false
        foreach ($f in @('Yes','NoAutostart','Widget','NoStart','Quiet')) { (Resolve-AgentViewInstallOptions @{ $f=$true } @{} $true $none).Ask | Should Be $false }
        (Resolve-AgentViewInstallOptions @{} @{ AGENT_VIEW_YES='1' } $true $none).Ask | Should Be $false
        (Resolve-AgentViewInstallOptions @{} @{ AGENT_VIEW_YES='0' } $true $none).Ask | Should Be $true
    }
    It 'uses defaults for a fresh install and applies flags or variables' {
        $o = Resolve-AgentViewInstallOptions @{ Yes=$true } @{} $false $none
        $o.Autostart | Should Be $true; $o.Widget | Should Be $false; $o.Start | Should Be $true; $o.Quiet | Should Be $false
        $o = Resolve-AgentViewInstallOptions @{} @{ AGENT_VIEW_NO_AUTOSTART='true'; AGENT_VIEW_WIDGET='1'; AGENT_VIEW_NO_START='yes'; AGENT_VIEW_QUIET='on' } $false $none
        $o.Autostart | Should Be $false; $o.Widget | Should Be $true; $o.Start | Should Be $false; $o.Quiet | Should Be $true
    }
    It 'keeps the current choices when updating an existing install' {
        $o = Resolve-AgentViewInstallOptions @{ Yes=$true } @{} $false ([pscustomobject]@{ Installed=$true; Autostart=$false; Widget=$true })
        $o.Autostart | Should Be $false; $o.Widget | Should Be $true
    }
    It 'parses yes/no answers with Enter as default' {
        ConvertFrom-AgentViewYesNo '' $true | Should Be $true
        ConvertFrom-AgentViewYesNo '  ' $false | Should Be $false
        ConvertFrom-AgentViewYesNo 'Y' $false | Should Be $true
        ConvertFrom-AgentViewYesNo 'có' $false | Should Be $true
        ConvertFrom-AgentViewYesNo 'n' $true | Should Be $false
        ConvertFrom-AgentViewYesNo 'không' $true | Should Be $false
        ($null -eq (ConvertFrom-AgentViewYesNo 'maybe' $true)) | Should Be $true
    }
}

Describe 'Install payload and staging' {
    It 'includes all modules including Cli.ps1 and rejects missing local files' {
        $text=Get-Content "$PSScriptRoot/../installer.ps1" -Raw -Encoding UTF8
        foreach ($name in @('I18n.ps1','Theme.ps1','Format.ps1','Ring.ps1','Popup.ps1','Widget.ps1','Settings.ps1','SettingsWindow.ps1','History.ps1','Forecast.ps1','Notify.ps1','Version.ps1','Cli.ps1')) { $text | Should Match ([regex]::Escape("'"+$name+"'")) }
        $text | Should Match 'Thiếu file cài đặt'
    }
    It 'picks the repo, a local source folder, or a URL' {
        $repo = Resolve-Path "$PSScriptRoot/.."
        (Get-AgentViewPayloadSource '' $repo).Local | Should Be $true
        (Get-AgentViewPayloadSource '' '').Base | Should Match '^https://'
        (Get-AgentViewPayloadSource "$TestDrive" '').Local | Should Be $true
        (Get-AgentViewPayloadSource 'https://example.test/x/' '').Base | Should Be 'https://example.test/x'
    }
    It 'stages the full repo payload and fails before touching the install dir when a file is missing' {
        $repo = Resolve-Path "$PSScriptRoot/.."
        $n = Save-AgentViewPayload ([pscustomobject]@{ Local=$true; Base=$repo }) "$TestDrive/stage"
        $n | Should Be 18
        Test-Path "$TestDrive/stage/I18n.ps1" | Should Be $true
        Test-Path "$TestDrive/stage/Cli.ps1" | Should Be $true
        Test-Path "$TestDrive/stage/Version.ps1" | Should Be $true
        Test-Path "$TestDrive/stage/uninstall.ps1" | Should Be $true
        New-Item -ItemType Directory -Force "$TestDrive/partial/src" | Out-Null
        Set-Content "$TestDrive/partial/src/Tray.ps1" 'x'
        { Save-AgentViewPayload ([pscustomobject]@{ Local=$true; Base="$TestDrive/partial" }) "$TestDrive/stage2" } | Should Throw 'Thiếu file cài đặt'
    }
    It 'installs staged files and the launcher, restoring old files on failure' {
        $repo = Resolve-Path "$PSScriptRoot/.."
        [void](Save-AgentViewPayload ([pscustomobject]@{ Local=$true; Base=$repo }) "$TestDrive/st3")
        $paths = Get-AgentViewPaths "$TestDrive/inst" "$TestDrive/startup"
        (Install-AgentViewFiles "$TestDrive/st3" $paths) | Should Be 18
        Test-Path $paths.Launcher | Should Be $true
        Set-Content $paths.Entry 'OLD'
        Remove-Item "$TestDrive/st3/Widget.ps1"
        { Install-AgentViewFiles "$TestDrive/st3" $paths } | Should Throw
        (Get-Content $paths.Entry -Raw).Trim() | Should Be 'OLD'
    }
    It 'summarises only readable quotas' {
        $s = [pscustomobject]@{ quotas=@([pscustomobject]@{ name='Claude Code'; ok=$true; remaining=72 }, [pscustomobject]@{ name='Codex'; ok=$false; remaining=$null }) }
        Format-AgentViewQuotaSummary $s | Should Be 'Quota còn lại: Claude Code 72%'
        ($null -eq (Format-AgentViewQuotaSummary ([pscustomobject]@{ quotas=@() }))) | Should Be $true
    }
    It 'builds a toast script with the PowerShell AppUserModelID and a balloon fallback' {
        $s = Get-AgentViewToastScript 'agent-view đang chạy' 'Bấm <icon> & xem'
        $s | Should Match 'WindowsPowerShell\\v1\.0\\powershell\.exe'
        $s | Should Match 'ShowBalloonTip'
        $s | Should Match '&lt;icon&gt; &amp; xem'
        $null = [scriptblock]::Create($s)
    }
}
