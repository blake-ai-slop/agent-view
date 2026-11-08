# Kiểm tra cập nhật nối vào tray, toast, popup — hàm THẬT (Tray/Toast/Popup/Update). Không mạng: Invoke-WebRequest bị chặn,
# Fetch/Job giả. Start-AgentViewUpdate được mock. Teardown: Close-AgentViewToast -Force, Close-AgentViewPopup -Force.
. "$PSScriptRoot/../src/Tray.ps1"

function New-FakeNotify {
    $o = [pscustomobject]@{ Icon = $null; Text = ''; Balloons = (New-Object System.Collections.ArrayList) }
    $o | Add-Member -MemberType ScriptMethod -Name ShowBalloonTip -Value {
        param($Timeout, $Title, $Text, $Icon)
        [void]$this.Balloons.Add([pscustomobject]@{ Title = $Title; Text = $Text; Icon = $Icon })
    }
    $o
}
function New-UpdateTray {
    $tray = @{ State = @{ Rows = @(); View = @(); Worker = $null; Pending = $null; Last = [datetime]::MinValue; Frame = 0; Loading = $false; RefreshSeconds = 120 }
        Notify = (New-FakeNotify); Menu = (New-AgentViewTrayMenu); Animation = $null; Begin = $null; OpenPopup = $null
        Update = (New-AgentViewUpdateTrayState); InstallUpdate = { Start-AgentViewUpdate } }
    $tray.Menu.UpdateState = $tray.Update
    Set-AgentViewUpdateMenu $tray.Menu
    $tray
}
function Wait-UpdateWorker($Tray) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($Tray.Update.Worker -and -not $Tray.Update.Pending.IsCompleted -and $sw.ElapsedMilliseconds -lt 20000) { Start-Sleep -Milliseconds 50 }
}
function Reset-UpdateUi {
    try { Close-AgentViewToast -Force } catch { }
    try { Close-AgentViewPopup -Force } catch { }
    [AppDomain]::CurrentDomain.SetData('agent-view.toast', $null)
    [AppDomain]::CurrentDomain.SetData('agent-view.popup', $null)
}
function Get-NextVersion { $p = $script:AgentViewVersion.Split('.'); '{0}.{1}.{2}' -f $p[0], $p[1], ([int]$p[2] + 1) }

Describe 'Update UI: tray menu, toast, popup chip' {
    $savedLocal = $env:LOCALAPPDATA; $savedSource = $env:AGENT_VIEW_SOURCE
    $savedLanguage = [AppDomain]::CurrentDomain.GetData('agent-view.language')
    BeforeEach {
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force)
        $env:AGENT_VIEW_SOURCE = 'https://raw.githubusercontent.com/example/agent-view/main'
        Reset-UpdateUi
        Set-AgentViewLanguage vi
        Mock Invoke-WebRequest { throw 'Tests must not access the network' }
        Mock Start-AgentViewUpdate { }
        Mock Test-AgentViewUserBusy { $false }
    }
    AfterEach { Reset-UpdateUi }

    It 'puts the update item right above Quit and switches to install when a newer version is known' {
        $tray = New-UpdateTray
        try {
            $items = $tray.Menu.Strip.Items
            $items[$items.Count - 1] | Should Be $tray.Menu.Exit
            $items[$items.Count - 2] | Should Be $tray.Menu.Update
            $tray.Menu.Update.Text | Should Be 'Kiểm tra cập nhật'
            $tray.Menu.Update.Enabled | Should Be $true
            [void](Complete-AgentViewUpdateCheck $tray @{ Status = 'newer'; Current = $script:AgentViewVersion; Latest = '9.9.9'; Url = 'u'; ShouldNotify = $false })
            $tray.Menu.Update.Text | Should Be 'Cập nhật lên v9.9.9'
            Invoke-AgentViewUpdateMenu $tray | Should Be 'install'
            Assert-MockCalled Start-AgentViewUpdate -Times 1 -Exactly -Scope It
            [void](Complete-AgentViewUpdateCheck $tray @{ Status = 'latest'; Current = '9.9.9'; Latest = '9.9.9'; ShouldNotify = $false })
            $tray.Menu.Update.Text | Should Be 'Kiểm tra cập nhật'
        } finally { $tray.Menu.Strip.Dispose() }
    }
    It 'reads a newer version from saved state at startup' {
        Save-AgentViewUpdateState @{ LastCheck = (Get-Date).ToUniversalTime().ToString('o'); LatestVersion = '9.0.0'; LatestUrl = 'u'; NotifiedVersion = '9.0.0' }
        $tray = New-UpdateTray
        try {
            $tray.Update.Latest | Should Be '9.0.0'
            $tray.Menu.Update.Text | Should Be 'Cập nhật lên v9.0.0'
        } finally { $tray.Menu.Strip.Dispose() }
        Save-AgentViewUpdateState @{ LastCheck = (Get-Date).ToUniversalTime().ToString('o'); LatestVersion = $script:AgentViewVersion; LatestUrl = 'u'; NotifiedVersion = $null }
        (New-AgentViewUpdateTrayState).Latest | Should Be $null
    }
    It 'changes the menu language through $apply' {
        $tray = New-UpdateTray
        $tray.Begin = { }
        try {
            Invoke-AgentViewSettingsApply -Settings ([pscustomobject]@{ Language = 'en' }) -Tray $tray
            $tray.Menu.Update.Text | Should Be 'Check for updates'
            $tray.Update.Latest = '9.9.9'
            Invoke-AgentViewSettingsApply -Settings ([pscustomobject]@{ Language = 'vi' }) -Tray $tray
            $tray.Menu.Update.Text | Should Be 'Cập nhật lên v9.9.9'
            Invoke-AgentViewSettingsApply -Settings ([pscustomobject]@{ Language = 'en' }) -Tray $tray
            $tray.Menu.Update.Text | Should Be 'Update to v9.9.9'
        } finally { $tray.Menu.Strip.Dispose() }
    }
    It 'manual check runs in the background with -Force, shows Checking… disabled, then one toast' {
        $tray = New-UpdateTray
        $tray.Update.Job = { param($path, $force, $language) Start-Sleep -Milliseconds 300; @{ Status = 'latest'; Current = '0.2.1'; Latest = '0.2.1'; ShouldNotify = $false; Forced = $force; Lang = $language } }
        try {
            Invoke-AgentViewUpdateMenu $tray | Should Be 'check'
            $tray.Update.Force | Should Be $true
            $tray.Menu.Update.Text | Should Be 'Đang kiểm tra…'
            $tray.Menu.Update.Enabled | Should Be $false
            Invoke-AgentViewUpdateMenu $tray | Should Be 'none'
            Wait-UpdateWorker $tray
            Receive-AgentViewUpdateCheck $tray | Should Be 'toast'
            $tray.Update.Worker | Should Be $null
            $tray.Menu.Update.Text | Should Be 'Kiểm tra cập nhật'
            $tray.Menu.Update.Enabled | Should Be $true
            (Get-AgentViewToastState).Model.Rows[0].Title | Should Be 'Đang dùng bản mới nhất (v0.2.1)'
            Assert-MockCalled Start-AgentViewUpdate -Times 0 -Scope It
        } finally { $tray.Menu.Strip.Dispose() }
    }
    It 'manual check goes through the real background runspace and Update.ps1 (no network: unsupported source)' {
        $env:AGENT_VIEW_SOURCE = $TestDrive
        $tray = New-UpdateTray
        try {
            Start-AgentViewUpdateCheck $tray -Manual | Should Be $true
            Wait-UpdateWorker $tray
            Receive-AgentViewUpdateCheck $tray | Should Be 'toast'
            (Get-AgentViewToastState).Model.Rows[0].Title | Should Be 'Nguồn cài đặt này không hỗ trợ kiểm tra cập nhật'
        } finally { $tray.Menu.Strip.Dispose() }
    }
    It 'manual results toast all three states with the real check (mocked fetch)' {
        $tray = New-UpdateTray
        $next = Get-NextVersion
        try {
            $r = Invoke-AgentViewUpdateCheck -Force -Fetch { param($u) @{ Version = $next; Url = "https://github.com/example/agent-view/releases/tag/v$next" } }.GetNewClosure()
            $r.Status | Should Be 'newer'
            Complete-AgentViewUpdateCheck $tray $r -Manual | Should Be 'toast'
            $st = Get-AgentViewToastState
            $st.Model.Rows[0].Title | Should Be "Có bản mới: v$next"
            $st.Model.Rows[0].Text | Should Be 'Bấm để cập nhật'
            $st.Model.Rows[0].Kind | Should Be 'update'
            $st.Model.Rows[0].Center | Should Be ([string][char]0x2191)
            $st.Model.Rows[0].Remaining | Should Be $null
            $st.Model.Warning | Should Be $false
            # bấm toast ⇒ cập nhật
            $e = New-Object System.Windows.Input.MouseButtonEventArgs ([System.Windows.Input.Mouse]::PrimaryDevice), 0, ([System.Windows.Input.MouseButton]::Left)
            $e.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
            $st.Ui.Shell.RaiseEvent($e)
            Assert-MockCalled Start-AgentViewUpdate -Times 1 -Exactly -Scope It

            $r = Invoke-AgentViewUpdateCheck -Force -Fetch { param($u) @{ Version = $script:AgentViewVersion; Url = "https://github.com/example/agent-view/releases/tag/v1" } }
            $r.Status | Should Be 'latest'
            Complete-AgentViewUpdateCheck $tray $r -Manual | Should Be 'toast'
            $st.Model.Rows[0].Title | Should Be "Đang dùng bản mới nhất (v$($script:AgentViewVersion))"
            $st.Model.Rows[0].Text | Should Be ''
            $tray.Update.Latest | Should Be $null

            $r = Invoke-AgentViewUpdateCheck -Force -Fetch { throw 'offline' }
            $r.Status | Should Be 'error'
            Complete-AgentViewUpdateCheck $tray $r -Manual | Should Be 'toast'
            $st.Model.Rows[0].Title | Should Be 'Không kiểm tra được cập nhật'
            # bấm toast latest/error không cập nhật
            $st.Ui.Shell.RaiseEvent($e)
            Assert-MockCalled Start-AgentViewUpdate -Times 1 -Exactly -Scope It
        } finally { $tray.Menu.Strip.Dispose() }
    }
    Context 'own mocks: automatic check toasts once' {
        It 'automatic check toasts once on ShouldNotify and stays silent for repeats, skipped and error' {
            Mock Show-AgentViewToast { }
            $tray = New-UpdateTray
            $next = Get-NextVersion
            $now = Get-Date
            try {
                $r = Invoke-AgentViewUpdateCheck -Now $now -Fetch { param($u) @{ Version = $next; Url = "https://github.com/example/agent-view/releases/tag/v$next" } }.GetNewClosure()
                $r.ShouldNotify | Should Be $true
                Complete-AgentViewUpdateCheck $tray $r | Should Be 'toast'
                $tray.Menu.Update.Text | Should Be "Cập nhật lên v$next"
                $r = Invoke-AgentViewUpdateCheck -Now $now.AddHours(1) -Fetch { throw 'must not fetch before 24h' }
                $r.Status | Should Be 'skipped'
                Complete-AgentViewUpdateCheck $tray $r | Should Be $null
                $tray.Update.Latest | Should Be $next      # skipped giữ bản mới đã biết
                $r = Invoke-AgentViewUpdateCheck -Now $now.AddHours(25) -Fetch { param($u) @{ Version = $next; Url = "https://github.com/example/agent-view/releases/tag/v$next" } }.GetNewClosure()
                $r.Status | Should Be 'newer'; $r.ShouldNotify | Should Be $false
                Complete-AgentViewUpdateCheck $tray $r | Should Be $null
                $r = Invoke-AgentViewUpdateCheck -Now $now.AddHours(50) -Fetch { throw 'offline' }
                $r.Status | Should Be 'error'
                Complete-AgentViewUpdateCheck $tray $r | Should Be $null
                $r = Invoke-AgentViewUpdateCheck -Now $now.AddHours(80) -Settings ([pscustomobject]@{ UpdateCheck = $false }) -Fetch { throw 'disabled' }
                $r.Status | Should Be 'skipped'
                Complete-AgentViewUpdateCheck $tray $r | Should Be $null
                Assert-MockCalled Show-AgentViewToast -Times 1 -Exactly -Scope It
                $tray.Notify.Balloons.Count | Should Be 0
            } finally { $tray.Menu.Strip.Dispose() }
        }
    }
    It 'automatic timer waits 2 minutes, then hourly, and checks without -Force' {
        $tray = New-UpdateTray
        $tray.Update.Job = { param($path, $force, $language) @{ Status = 'skipped'; Current = '0.2.1'; ShouldNotify = $false; Forced = $force } }
        $timer = New-Object Windows.Forms.Timer
        try {
            (Get-AgentViewUpdateTimerPlan).FirstMs | Should Be 120000
            Invoke-AgentViewUpdateTimerTick $tray $timer
            $timer.Interval | Should Be 3600000
            $tray.Update.Force | Should Be $false
            $tray.Menu.Update.Text | Should Be 'Kiểm tra cập nhật'   # tự kiểm không đổi menu
            Wait-UpdateWorker $tray
            Receive-AgentViewUpdateCheck $tray | Should Be $null
            Test-AgentViewToastOpen | Should Be $false
        } finally { $timer.Dispose(); $tray.Menu.Strip.Dispose() }
    }
    It 'a manual click during an automatic check queues a forced check right after' {
        $tray = New-UpdateTray
        $tray.Update.Job = { param($path, $force, $language) Start-Sleep -Milliseconds 200; @{ Status = 'latest'; Current = '0.2.1'; Latest = '0.2.1'; ShouldNotify = $false } }
        try {
            Start-AgentViewUpdateCheck $tray | Should Be $true
            Invoke-AgentViewUpdateMenu $tray | Should Be 'check'
            $tray.Menu.Update.Text | Should Be 'Đang kiểm tra…'
            Wait-UpdateWorker $tray
            Receive-AgentViewUpdateCheck $tray | Should Be $null     # kết quả tự kiểm: im lặng
            $tray.Update.Force | Should Be $true                      # kiểm tay đã chạy
            Wait-UpdateWorker $tray
            Receive-AgentViewUpdateCheck $tray | Should Be 'toast'
        } finally { $tray.Menu.Strip.Dispose() }
    }
    It 'treats a failing runspace as an error result' {
        $tray = New-UpdateTray
        $tray.Update.Job = { param($path, $force, $language) throw 'boom' }
        try {
            [void](Start-AgentViewUpdateCheck $tray -Manual)
            Wait-UpdateWorker $tray
            Receive-AgentViewUpdateCheck $tray | Should Be 'toast'
            (Get-AgentViewToastState).Model.Rows[0].Title | Should Be 'Không kiểm tra được cập nhật'
        } finally { $tray.Menu.Strip.Dispose() }
    }
    Context 'own mocks: falls back to a balloon when the user is busy' {
        It 'falls back to a balloon when the user is busy' {
            Mock Test-AgentViewUserBusy { $true }
            Mock Show-AgentViewToast { throw 'must not be called' }
            Set-AgentViewLanguage en
            $tray = New-UpdateTray
            try {
                Complete-AgentViewUpdateCheck $tray @{ Status = 'newer'; Current = '0.2.1'; Latest = '9.9.9'; Url = 'u'; ShouldNotify = $true } | Should Be 'balloon'
                $tray.Notify.Balloons.Count | Should Be 1
                $tray.Notify.Balloons[0].Title | Should Be 'Update available: v9.9.9'
                $tray.Notify.Balloons[0].Text | Should Be 'Click to update'
                $tray.Notify.Balloons[0].Icon | Should Be ([Windows.Forms.ToolTipIcon]::Info)
            } finally { $tray.Menu.Strip.Dispose() }
        }
    }
    It 'builds the update toast window in en and vi with an arrow instead of a percentage ring' {
        foreach ($lang in 'en', 'vi') {
            Set-AgentViewLanguage $lang
            { Show-AgentViewToast -Items @(Get-AgentViewUpdateToastItem @{ Status = 'newer'; Current = '0.2.1'; Latest = '0.2.2' }) } | Should Not Throw
            $st = Get-AgentViewToastState
            $st.Ui.Rows.Children.Count | Should Be 1
            $icon = $st.Ui.Rows.Children[0].Child.Children[0]
            $icon -is [System.Windows.Controls.Canvas] | Should Be $true
            @($icon.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] }).Count | Should Be 0
            Reset-UpdateUi
        }
    }
    It 'shows the popup chip only with a version and OnUpdate; clicking it updates' {
        $hits = @{ n = 0 }
        Show-AgentViewPopup -Rows @()
        $st = Get-AgentViewPopupState
        $st.Ui.UpdateChip.Visibility | Should Be 'Collapsed'
        Close-AgentViewPopup -Force
        Show-AgentViewPopup -Rows @() -UpdateVersion '0.2.2'
        $st.Ui.UpdateChip.Visibility | Should Be 'Collapsed'
        Close-AgentViewPopup -Force
        Show-AgentViewPopup -Rows @() -UpdateVersion '0.2.2' -OnUpdate ({ $hits.n++ }.GetNewClosure())
        $st.Ui.UpdateChip.Visibility | Should Be 'Visible'
        $st.Ui.UpdateChipText.Text | Should Be ('v0.2.2 ' + [char]0x2191)
        $st.Ui.UpdateChip.ToolTip | Should Be 'Có bản mới: v0.2.2'
        $e = New-Object System.Windows.Input.MouseButtonEventArgs ([System.Windows.Input.Mouse]::PrimaryDevice), 0, ([System.Windows.Input.MouseButton]::Left)
        $e.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
        $st.Ui.UpdateChip.RaiseEvent($e)
        $hits.n | Should Be 1
        Set-AgentViewPopupUpdate -Version $null
        $st.Ui.UpdateChip.Visibility | Should Be 'Collapsed'
    }
    It 'tray completion shows and hides the chip on an open popup and the chip calls Start-AgentViewUpdate' {
        $tray = New-UpdateTray
        try {
            Show-AgentViewPopup -Rows @()
            $st = Get-AgentViewPopupState
            [void](Complete-AgentViewUpdateCheck $tray @{ Status = 'newer'; Current = '0.2.1'; Latest = '0.3.0'; Url = 'u'; ShouldNotify = $false })
            $st.Ui.UpdateChip.Visibility | Should Be 'Visible'
            $e = New-Object System.Windows.Input.MouseButtonEventArgs ([System.Windows.Input.Mouse]::PrimaryDevice), 0, ([System.Windows.Input.MouseButton]::Left)
            $e.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
            $st.Ui.UpdateChip.RaiseEvent($e)
            Assert-MockCalled Start-AgentViewUpdate -Times 1 -Exactly -Scope It
            [void](Complete-AgentViewUpdateCheck $tray @{ Status = 'latest'; Current = '0.3.0'; Latest = '0.3.0'; ShouldNotify = $false })
            $st.Ui.UpdateChip.Visibility | Should Be 'Collapsed'
        } finally { $tray.Menu.Strip.Dispose() }
    }
    $env:LOCALAPPDATA = $savedLocal; $env:AGENT_VIEW_SOURCE = $savedSource
    [AppDomain]::CurrentDomain.SetData('agent-view.language', $savedLanguage)
}
