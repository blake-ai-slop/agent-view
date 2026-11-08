# Tích hợp giai đoạn B với hàm THẬT: Tray (Complete/Apply) + History + Forecast + Notify + I18n + Popup/Widget.
# Chỉ NotifyIcon được thay bằng bản giả ghi lại ShowBalloonTip. Mọi file ghi vào TestDrive (LOCALAPPDATA tạm).
. "$PSScriptRoot/../src/Tray.ps1"

function New-FakeNotify {
    $o = [pscustomobject]@{ Icon = $null; Text = ''; Balloons = (New-Object System.Collections.ArrayList) }
    $o | Add-Member -MemberType ScriptMethod -Name ShowBalloonTip -Value {
        param($Timeout, $Title, $Text, $Icon)
        [void]$this.Balloons.Add([pscustomobject]@{ Title = $Title; Text = $Text; Icon = $Icon })
    }
    $o
}
function New-FakeTray {
    @{ State = @{ Rows = @(); View = @(); Worker = $null; Pending = $null; Last = [datetime]::MinValue; Frame = 0; Loading = $false; RefreshSeconds = 120 }
       Notify = (New-FakeNotify); Menu = $null; Animation = $null; Begin = $null; OpenPopup = $null }
}
function New-IntRow([string]$Provider, $Five, $Week, [datetime]$FiveReset, [datetime]$WeekReset) {
    $name = @{ claude = 'Claude Code'; codex = 'Codex' }[$Provider]
    [pscustomobject]@{ Provider = $Provider; Name = $name; Ok = $true; Error = $null; FiveHourUsed = $Five; WeekUsed = $Week
        FiveHourResetsAt = $FiveReset; WeekResetsAt = $WeekReset; FetchedAt = (Get-Date) }
}
function Reset-IntegrateState {
    try { Close-AgentViewPopup -Force } catch { }
    try { Hide-AgentViewWidget } catch { }
    [AppDomain]::CurrentDomain.SetData('agent-view.popup', $null)
    [AppDomain]::CurrentDomain.SetData('agent-view.widget', $null)
}

Describe 'Integration: refresh → history, forecast, notifications, hidden providers' {
    $savedLocal = $env:LOCALAPPDATA
    $savedLanguage = [AppDomain]::CurrentDomain.GetData('agent-view.language')
    BeforeEach {
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force)
        Reset-IntegrateState
        Set-AgentViewLanguage en
        Initialize-AgentViewTrayNative
    }
    AfterEach { Reset-IntegrateState }

    It 'builds a forecast line in the popup model after three refreshes with a usage rate' {
        $tray = New-FakeTray
        $now = Get-Date
        $fiveReset = $now.AddHours(2); $weekReset = $now.AddDays(3)
        $steps = @(@(-20, 40), @(-10, 50), @(0, 60))
        foreach ($step in $steps) {
            Complete-AgentViewRefresh $tray @((New-IntRow 'claude' $step[1] 10 $fiveReset $weekReset)) -Now $now.AddMinutes($step[0])
        }
        @(Get-AgentViewHistory).Count | Should Be 6
        $row = $tray.State.View[0]
        $model = Get-AgentViewCardModel $row -Now $now -History (Get-AgentViewPopupHistory)
        $model.Five.ForecastKind | Should Be 'runout'
        $model.Five.ForecastText | Should Match '^Runs out ~\d\d:\d\d$'
        ([datetime]$model.Five.ForecastAt - $now).TotalMinutes | Should BeGreaterThan 35
        ([datetime]$model.Five.ForecastAt - $now).TotalMinutes | Should BeLessThan 45
        $model.Week.ForecastKind | Should Be 'unknown'      # tốc độ 0 ⇒ ẩn
        # Không truyền History ⇒ không có dòng dự báo (tương thích model cũ).
        (Get-AgentViewCardModel $row -Now $now).Five.ForecastKind | Should Be 'unknown'
        # Widget: thêm "out ~HH:mm" cho cửa sổ sát nhất (5h còn 40%).
        Get-AgentViewWidgetDetailText $model $now | Should Match ' · out ~\d\d:\d\d$'

        # Popup thật: dòng dự báo hiện dưới reset 5h (màu warn), ẩn ở tuần.
        [void](New-AgentViewPopupWindow)
        $st = Get-AgentViewPopupState
        $st.Rows = $tray.State.View
        Update-AgentViewPopupView 'static'
        $card = $st.Cards['claude']
        $card.FiveForecast.Visibility | Should Be 'Visible'
        $card.FiveForecast.Text | Should Be $model.Five.ForecastText
        $card.FiveForecast.Foreground.Color.ToString() | Should Be ('#FF' + (Get-AgentViewTheme)['warn'].TrimStart('#'))
        $card.WeekForecast.Visibility | Should Be 'Collapsed'
    }

    It 'colors enough in secondary text and runout in crit for a critical window' {
        $theme = Get-AgentViewTheme
        Get-AgentViewForecastColorKey ([pscustomobject]@{ ForecastKind = 'enough'; Level = 'ok' }) | Should Be 'av-text-3'
        Get-AgentViewForecastColorKey ([pscustomobject]@{ ForecastKind = 'runout'; Level = 'crit' }) | Should Be 'crit'
        Get-AgentViewForecastColorKey ([pscustomobject]@{ ForecastKind = 'runout'; Level = 'ok' }) | Should Be 'warn'
        Get-AgentViewForecastColorKey ([pscustomobject]@{ ForecastKind = 'unknown'; Level = 'ok' }) | Should Be $null
        $theme.ContainsKey('av-text-3') | Should Be $true
    }

    It 'shows exactly one merged balloon when thresholds are crossed and does not repeat' {
        $tray = New-FakeTray
        $now = Get-Date
        $fiveReset = $now.AddHours(2); $weekReset = $now.AddDays(3)
        Complete-AgentViewRefresh $tray @((New-IntRow 'claude' 20 10 $fiveReset $weekReset), (New-IntRow 'codex' 20 10 $fiveReset $weekReset)) -Now $now.AddMinutes(-5)
        $tray.Notify.Balloons.Count | Should Be 0
        # Cả hai provider xuống 25% còn lại cùng lúc ⇒ đúng 1 balloon gộp, mức Info (25 > ngưỡng thấp 10).
        Complete-AgentViewRefresh $tray @((New-IntRow 'claude' 75 10 $fiveReset $weekReset), (New-IntRow 'codex' 75 10 $fiveReset $weekReset)) -Now $now.AddMinutes(-4)
        $tray.Notify.Balloons.Count | Should Be 1
        $b = $tray.Notify.Balloons[0]
        $b.Icon | Should Be ([Windows.Forms.ToolTipIcon]::Info)
        $b.Title | Should Be 'agent-view'
        $b.Text | Should Match 'Claude Code: 25% left'
        $b.Text | Should Match 'Codex: 25% left'
        # Lặp lại cùng số liệu ⇒ không báo lại (state lưu thật trên đĩa).
        Complete-AgentViewRefresh $tray @((New-IntRow 'claude' 76 10 $fiveReset $weekReset), (New-IntRow 'codex' 76 10 $fiveReset $weekReset)) -Now $now.AddMinutes(-3)
        $tray.Notify.Balloons.Count | Should Be 1
        Test-Path (Get-AgentViewNotifyStatePath) | Should Be $true
        # Một provider xuống ≤10 ⇒ 1 balloon Warning, tiêu đề là chính thông báo.
        Complete-AgentViewRefresh $tray @((New-IntRow 'claude' 92 10 $fiveReset $weekReset), (New-IntRow 'codex' 76 10 $fiveReset $weekReset)) -Now $now.AddMinutes(-2)
        $tray.Notify.Balloons.Count | Should Be 2
        $tray.Notify.Balloons[1].Icon | Should Be ([Windows.Forms.ToolTipIcon]::Warning)
        $tray.Notify.Balloons[1].Title | Should Be 'Claude Code: 8% left'
    }

    It 'keeps hidden providers out of icon, tooltip, popup and notifications but records their history' {
        $tray = New-FakeTray
        (Get-AgentViewWidgetState).Settings | Add-Member -NotePropertyName HiddenProviders -NotePropertyValue @('codex') -Force
        $now = Get-Date
        $fiveReset = $now.AddHours(2); $weekReset = $now.AddDays(3)
        Complete-AgentViewRefresh $tray @((New-IntRow 'claude' 30 20 $fiveReset $weekReset), (New-IntRow 'codex' 95 20 $fiveReset $weekReset)) -Now $now
        @($tray.State.Rows).Count | Should Be 2
        @($tray.State.View | ForEach-Object { $_.Provider }) -join ',' | Should Be 'claude'
        Get-QuotaTrayRemaining $tray.State.View | Should Be 70
        $tray.Notify.Text | Should Not Match 'Codex'
        $tray.Notify.Text | Should Match 'Claude 70%'
        @((Get-AgentViewPopupState).Rows | ForEach-Object { $_.Provider }) -join ',' | Should Be 'claude'
        $tray.Notify.Balloons.Count | Should Be 0           # codex 5% còn lại nhưng bị ẩn
        @(Get-AgentViewHistory | Where-Object { $_.p -eq 'codex' }).Count | Should Be 2
        $tray.Notify.Icon | Should Not BeNullOrEmpty
    }

    It 'swallows history and notify I/O failures without breaking the refresh' {
        $tray = New-FakeTray
        # LOCALAPPDATA trỏ vào một FILE ⇒ mọi ghi history/state đều lỗi.
        $blocker = Join-Path $TestDrive ('blocker-' + [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $blocker -Value 'x'
        $env:LOCALAPPDATA = $blocker
        $now = Get-Date
        { Complete-AgentViewRefresh $tray @((New-IntRow 'claude' 80 20 $now.AddHours(2) $now.AddDays(3))) -Now $now } | Should Not Throw
        @($tray.State.View).Count | Should Be 1
        $tray.Notify.Text | Should Match 'Claude 20%'
    }
    $env:LOCALAPPDATA = $savedLocal
    [AppDomain]::CurrentDomain.SetData('agent-view.language', $savedLanguage)
}

Describe 'Integration: settings apply and refresh interval' {
    $savedLocal = $env:LOCALAPPDATA
    $savedLanguage = [AppDomain]::CurrentDomain.GetData('agent-view.language')
    BeforeEach {
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force)
        Reset-IntegrateState
        Set-AgentViewLanguage en
        Initialize-AgentViewTrayNative
    }
    AfterEach { Reset-IntegrateState }

    It 'reads RefreshSeconds with a safe default' {
        Get-AgentViewRefreshSeconds $null | Should Be 120
        Get-AgentViewRefreshSeconds ([pscustomobject]@{ WidgetEnabled = $false }) | Should Be 120
        Get-AgentViewRefreshSeconds ([pscustomobject]@{ RefreshSeconds = 60 }) | Should Be 60
        Get-AgentViewRefreshSeconds @{ RefreshSeconds = 300 } | Should Be 300
        Get-AgentViewRefreshSeconds ([pscustomobject]@{ RefreshSeconds = 45 }) | Should Be 120
        Get-AgentViewRefreshSeconds ([pscustomobject]@{ RefreshSeconds = 'x' }) | Should Be 120
    }

    It 'changes the refresh cycle, menu language and refreshes immediately through $apply' {
        $tray = New-FakeTray
        $hits = @{ n = 0 }
        $tray.Begin = { $hits.n++ }.GetNewClosure()
        $tray.Menu = New-AgentViewTrayMenu
        try {
            $tray.Menu.Settings | Should Not BeNullOrEmpty
            $tray.Menu.Strip.Items[0] | Should Be $tray.Menu.Settings      # đầu menu
            $tray.Menu.Settings.Text | Should Be 'Settings…'
            $tray.Menu.Refresh.Text | Should Be 'Refresh'
            $now = Get-Date
            $tray.State.Last = $now.AddSeconds(-200)
            Test-AgentViewRefreshDue $tray.State $now | Should Be $true
            # Như $tray.Apply trong Start-AgentView (closure của Pester không thấy hàm script-scope nên gọi trực tiếp).
            $apply = { param($saved) Invoke-AgentViewSettingsApply -Settings $saved -Tray $tray }
            & $apply ([pscustomobject]@{ Language = 'vi'; RefreshSeconds = 300; WidgetEnabled = $false; HiddenProviders = @() })
            $tray.State.RefreshSeconds | Should Be 300
            Test-AgentViewRefreshDue $tray.State $now | Should Be $false
            Test-AgentViewRefreshDue $tray.State $now.AddSeconds(101) | Should Be $true
            $tray.Menu.Settings.Text | Should Be 'Cài đặt…'
            $tray.Menu.Refresh.Text | Should Be 'Làm mới'
            $tray.Menu.Exit.Text | Should Be 'Thoát'
            $tray.Notify.Text | Should Be 'Đang cập nhật quota'
            $hits.n | Should Be 1
            (Get-AgentViewWidgetState).Settings.RefreshSeconds | Should Be 300
            & $apply ([pscustomobject]@{ Language = 'en'; RefreshSeconds = 60 })
            $tray.State.RefreshSeconds | Should Be 60
            $tray.Menu.Refresh.Text | Should Be 'Refresh'
            $hits.n | Should Be 2
        } finally { $tray.Menu.Strip.Dispose() }
    }

    It 'applies a save from the real settings window through $tray.Apply' {
        $savedStartup = $env:AGENT_VIEW_STARTUP_DIR
        $env:AGENT_VIEW_STARTUP_DIR = Join-Path $TestDrive ('startup-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $env:AGENT_VIEW_STARTUP_DIR -Force)
        $tray = New-FakeTray
        $hits = @{ n = 0 }
        $tray.Begin = { $hits.n++ }.GetNewClosure()
        $tray.Menu = New-AgentViewTrayMenu
        $tray.Apply = { param($saved) Invoke-AgentViewSettingsApply -Settings $saved -Tray $tray }
        $now = Get-Date
        $tray.State.Rows = @((New-IntRow 'claude' 30 20 $now.AddHours(2) $now.AddDays(3)), (New-IntRow 'codex' 50 20 $now.AddHours(2) $now.AddDays(3)))
        try {
            Show-AgentViewSettingsWindow -OnSaved $tray.Apply
            $ui = (Get-AgentViewSettingsWindowState).Ui
            $ui.LangVi.IsChecked = $true; $ui.Refresh60.IsChecked = $true; $ui.Codex.IsChecked = $false; $ui.WidgetEnabled.IsChecked = $false
            # SettingsWindow.ps1 (w2) phát thêm 1 giá trị trước $true; chỉ kiểm giá trị cuối.
            @(Save-AgentViewSettingsWindow)[-1] | Should Be $true
            $tray.Menu.Refresh.Text | Should Be 'Làm mới'
            $tray.Menu.Settings.Text | Should Be 'Cài đặt…'
            $tray.State.RefreshSeconds | Should Be 60
            @($tray.State.View | ForEach-Object { $_.Provider }) -join ',' | Should Be 'claude'
            $tray.Notify.Text | Should Not Match 'Codex'
            $hits.n | Should Be 1
            (Get-AgentViewSettings).Language | Should Be 'vi'
        } finally {
            Close-AgentViewSettingsWindow -Force
            $tray.Menu.Strip.Dispose()
            $env:AGENT_VIEW_STARTUP_DIR = $savedStartup
        }
    }

    It 'shows the popup gear only with -OnSettings and calls it on click' {
        $now = Get-Date
        $row = New-IntRow 'claude' 30 20 $now.AddHours(2) $now.AddDays(3)
        $hits = @{ n = 0 }
        Show-AgentViewPopup -Rows @($row)
        $st = Get-AgentViewPopupState
        $st.Ui.SettingsBtn.Visibility | Should Be 'Collapsed'
        Close-AgentViewPopup -Force
        Show-AgentViewPopup -Rows @($row) -OnSettings ({ $hits.n++ }.GetNewClosure())
        $st.Ui.SettingsBtn.Visibility | Should Be 'Visible'
        $st.Ui.SettingsBtn.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        $hits.n | Should Be 1
    }
    $env:LOCALAPPDATA = $savedLocal
    [AppDomain]::CurrentDomain.SetData('agent-view.language', $savedLanguage)
}
