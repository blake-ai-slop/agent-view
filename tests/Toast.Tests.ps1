# Toast agent-view THẬT (WPF) + Tray thật cho chỗ nối toast/balloon. Teardown: Close-AgentViewToast -Force.
. "$PSScriptRoot/../src/Tray.ps1"

function New-ToastItem([string]$Provider = 'claude', [int]$Remaining = 28, [string]$Kind = 'low', [string]$Title = $null, [string]$Text = '5-hour limit · resets 10:48') {
    if (-not $Title) { $Title = "$Provider : $Remaining" }
    @{ Provider = $Provider; Window = '5h'; Kind = $Kind; Remaining = $Remaining; Title = $Title; Text = $Text }
}
function Reset-ToastState {
    try { Close-AgentViewToast -Force } catch { }
    [AppDomain]::CurrentDomain.SetData('agent-view.toast', $null)
}
function New-FakeNotify {
    $o = [pscustomobject]@{ Balloons = (New-Object System.Collections.ArrayList) }
    $o | Add-Member -MemberType ScriptMethod -Name ShowBalloonTip -Value {
        param($Timeout, $Title, $Text, $Icon)
        [void]$this.Balloons.Add([pscustomobject]@{ Title = $Title; Text = $Text; Icon = $Icon })
    }
    $o
}

Describe 'Toast pure helpers' {
    It 'anchors the toast 12px from the work area corner including shadow margins' {
        $m = Get-AgentViewToastMetrics
        $p = Get-AgentViewToastPlacement ([pscustomobject]@{ Right = 1920; Bottom = 1032 }) 200
        $p.Left | Should Be (1920 - 12 - $m.Width - $m.ShadowLeft)
        $p.Top | Should Be (1032 - 12 + $m.ShadowBottom - 200)
        $m.Width | Should Be 344
    }
    It 'caps rows at four and reports +N in both languages' {
        $items = @(1..6 | ForEach-Object { New-ToastItem -Remaining (30 - $_) })
        Set-AgentViewLanguage en
        $m = Get-AgentViewToastModel $items
        $m.Rows.Count | Should Be 4; $m.More | Should Be 2; $m.MoreText | Should Be '+2 more'
        Set-AgentViewLanguage vi
        (Get-AgentViewToastModel $items).MoreText | Should Be '+2 thông báo khác'
        (Get-AgentViewToastModel @($items[0])).More | Should Be 0
    }
    It 'colors by remaining level and shows reset as a full ok ring with a check' {
        $rows = (Get-AgentViewToastModel @((New-ToastItem -Remaining 28), (New-ToastItem -Remaining 8), (New-ToastItem -Remaining 40 -Kind 'reset'), (New-ToastItem -Remaining 25 -Kind 'reset'))).Rows
        $rows[0].Level | Should Be 'warn'; $rows[0].Center | Should Be '28%'; $rows[0].Value | Should Be 28
        $rows[1].Level | Should Be 'crit'
        $rows[2].Level | Should Be 'ok'; $rows[2].Value | Should Be 100; $rows[2].Center | Should Be ([string][char]0x2713)
        $rows[3].Level | Should Be 'ok'
        Get-AgentViewToastProviderColor 'claude' | Should Be (Get-AgentViewTheme)['claude']
        Get-AgentViewToastProviderColor 'other' | Should Be (Get-AgentViewTheme)['accent']
    }
    It 'treats a failed busy query as not busy' {
        Initialize-AgentViewToastNative
        { Test-AgentViewUserBusy } | Should Not Throw
        (Test-AgentViewUserBusy) -is [bool] | Should Be $true
    }
}

Describe 'Toast window' {
    $savedLanguage = [AppDomain]::CurrentDomain.GetData('agent-view.language')
    BeforeEach { Reset-ToastState }
    AfterEach { Reset-ToastState }

    It 'builds en and vi toasts without error, without activation, inside the work area' {
        foreach ($lang in 'en', 'vi') {
            Set-AgentViewLanguage $lang
            { Show-AgentViewToast -Items @((New-ToastItem), (New-ToastItem 'codex' 7)) -Warning } | Should Not Throw
            $st = Get-AgentViewToastState
            $w = $st.Window
            $w.IsVisible | Should Be $true
            $w.ShowActivated | Should Be $false
            $w.Topmost | Should Be $true
            $w.ShowInTaskbar | Should Be $false
            $w.IsActive | Should Be $false
            $st.Ui.Rows.Children.Count | Should Be 2
            $st.Ui.NowText.Text | Should Be (T 'toast.now')
            $m = Get-AgentViewToastMetrics
            $wa = [System.Windows.SystemParameters]::WorkArea
            $st.Ui.Shell.Measure((New-Object System.Windows.Size $m.Width, ([double]::PositiveInfinity)))
            $left = $w.Left + $m.ShadowLeft; $right = $left + $m.Width
            $bottom = $w.Top + $st.Ui.Shell.DesiredSize.Height - $m.ShadowBottom   # DesiredSize gồm lề bóng
            $left | Should Not BeLessThan $wa.Left
            $right | Should Be ($wa.Right - 12)
            [math]::Round($bottom, 3) | Should Be ([math]::Round($wa.Bottom - 12, 3))
            $w.Top | Should Not BeLessThan $wa.Top
            Reset-ToastState
        }
        [AppDomain]::CurrentDomain.SetData('agent-view.language', $savedLanguage)
    }
    It 'shows +N for more than four items' {
        Set-AgentViewLanguage en
        Show-AgentViewToast -Items @(1..5 | ForEach-Object { New-ToastItem -Remaining (20 + $_) })
        $st = Get-AgentViewToastState
        $st.Ui.Rows.Children.Count | Should Be 4
        $st.Ui.MoreText.Visibility | Should Be 'Visible'
        $st.Ui.MoreText.Text | Should Be '+1 more'
    }
    It 'replaces content in the same single window when called again' {
        Show-AgentViewToast -Items @(New-ToastItem -Title 'first')
        $st = Get-AgentViewToastState
        $first = $st.Window
        Show-AgentViewToast -Items @((New-ToastItem -Title 'second'), (New-ToastItem 'codex' 9 -Title 'third')) -Warning
        [object]::ReferenceEquals($first, $st.Window) | Should Be $true
        $st.Ui.Rows.Children.Count | Should Be 2
        @($st.Model.Rows | ForEach-Object { $_.Title }) -join ',' | Should Be 'second,third'
        $st.Model.Warning | Should Be $true
        $st.Ui.DotHalo.Visibility | Should Be 'Visible'
        $st.LeftMs | Should Be (Get-AgentViewToastMetrics).HideMs
        $st.Timer.IsEnabled | Should Be $true
    }
    It 'clicking the body calls OnClick then hides; Hide keeps the window for reuse' {
        $hits = @{ n = 0 }
        Show-AgentViewToast -Items @(New-ToastItem) -OnClick { $hits.n++ }.GetNewClosure()
        $st = Get-AgentViewToastState
        $e = New-Object System.Windows.Input.MouseButtonEventArgs ([System.Windows.Input.Mouse]::PrimaryDevice), 0, ([System.Windows.Input.MouseButton]::Left)
        $e.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
        $st.Ui.Shell.RaiseEvent($e)
        $hits.n | Should Be 1
        Test-AgentViewToastOpen | Should Be $false
        $st.Closing | Should Be $true
        $st.Timer.IsEnabled | Should Be $false
    }
    It 'pausing the countdown keeps the remaining time and resuming restarts the timer' {
        Show-AgentViewToast -Items @(New-ToastItem)
        $st = Get-AgentViewToastState
        $st.LeftMs = 5000; $st.Clock = [Diagnostics.Stopwatch]::StartNew()
        Suspend-AgentViewToastCountdown
        $st.Timer.IsEnabled | Should Be $false
        $st.LeftMs | Should BeLessThan 5001
        $st.LeftMs | Should BeGreaterThan 4000
        $st.Ui.BarScale.ScaleX | Should BeLessThan 0.63
        Start-AgentViewToastCountdown
        $st.Timer.IsEnabled | Should Be $true
        $st.Timer.Interval.TotalMilliseconds | Should Be $st.LeftMs
    }
    It 'Close -Force disposes the window and is idempotent' {
        Show-AgentViewToast -Items @(New-ToastItem)
        Close-AgentViewToast -Force
        (Get-AgentViewToastState).Window | Should Be $null
        { Close-AgentViewToast -Force } | Should Not Throw
        { Hide-AgentViewToast } | Should Not Throw
    }
}

Describe 'Tray notification channel (toast vs balloon)' {
    BeforeEach { Reset-ToastState; Set-AgentViewLanguage en }
    AfterEach { Reset-ToastState }
    $items = @(@{ Provider = 'claude'; Window = '5h'; Kind = 'low'; Remaining = 8; Title = 'Claude Code: 8% left'; Text = '5-hour limit' })

    It 'uses the toast when the user is not busy' {
        Mock Test-AgentViewUserBusy { $false }
        $notify = New-FakeNotify
        $b = Get-AgentViewBalloon $items $null
        Show-AgentViewNotification $b $notify {} | Should Be 'toast'
        $notify.Balloons.Count | Should Be 0
        Test-AgentViewToastOpen | Should Be $true
        (Get-AgentViewToastState).Model.Warning | Should Be $true
    }
    It 'falls back to the balloon when the user is busy' {
        Mock Test-AgentViewUserBusy { $true }
        Mock Show-AgentViewToast { throw 'must not be called' }
        $notify = New-FakeNotify
        Show-AgentViewNotification (Get-AgentViewBalloon $items $null) $notify $null | Should Be 'balloon'
        $notify.Balloons.Count | Should Be 1
        $notify.Balloons[0].Title | Should Be 'Claude Code: 8% left'
        Assert-MockCalled Show-AgentViewToast -Times 0
    }
    It 'falls back to the balloon when the toast throws' {
        Mock Test-AgentViewUserBusy { $false }
        Mock Show-AgentViewToast { throw 'wpf broke' }
        $notify = New-FakeNotify
        Show-AgentViewNotification (Get-AgentViewBalloon $items $null) $notify $null | Should Be 'balloon'
        $notify.Balloons.Count | Should Be 1
        $notify.Balloons[0].Icon | Should Be ([Windows.Forms.ToolTipIcon]::Warning)
    }
    It 'refresh hooks route through the channel and record which one was used' {
        $saved = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force)
            Mock Test-AgentViewUserBusy { $true }
            $notify = New-FakeNotify
            $now = Get-Date
            $row = { param($used) [pscustomobject]@{ Provider = 'claude'; Name = 'Claude Code'; Ok = $true; Error = $null; FiveHourUsed = $used; WeekUsed = 1
                FiveHourResetsAt = $now.AddHours(2); WeekResetsAt = $now.AddDays(3); FetchedAt = $now } }
            [void](Invoke-AgentViewRefreshHooks -Rows @(& $row 10) -Settings $null -Notify $notify -Now $now.AddMinutes(-1))
            $b = Invoke-AgentViewRefreshHooks -Rows @(& $row 75) -Settings $null -Notify $notify -Now $now
            $b.Shown | Should Be 'balloon'
            $notify.Balloons.Count | Should Be 1
        } finally { $env:LOCALAPPDATA = $saved }
    }
}
