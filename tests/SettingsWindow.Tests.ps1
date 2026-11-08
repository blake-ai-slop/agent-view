. "$PSScriptRoot/../src/SettingsWindow.ps1"
Describe 'Settings window' {
    BeforeEach {
        $script:settingsOldLocal=$env:LOCALAPPDATA
        $env:LOCALAPPDATA=Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
        Set-AgentViewLanguage en
        Mock Test-AgentViewAutostart { $false }
        Mock Set-AgentViewAutostart {}
        Close-AgentViewSettingsWindow -Force
    }
    AfterEach {
        Close-AgentViewSettingsWindow -Force
        $env:LOCALAPPDATA=$script:settingsOldLocal
        Set-AgentViewLanguage auto
    }
    It 'opens one modeless Bezel window and reactivates it' {
        Show-AgentViewSettingsWindow
        $w=(Get-AgentViewSettingsWindowState).Window
        Show-AgentViewSettingsWindow
        [object]::ReferenceEquals($w,(Get-AgentViewSettingsWindowState).Window) | Should Be $true
        $w.IsVisible | Should Be $true
        $w.WindowStyle | Should Be None
        (Get-AgentViewSettingsWindowState).Ui.Shell.CornerRadius.TopLeft | Should Be 8
        (Get-AgentViewSettingsWindowState).Ui.Shell.Effect.BlurRadius | Should Be 32
        Close-AgentViewSettingsWindow -Force
        $w.IsVisible | Should Be $false
        (Get-AgentViewSettingsWindowState).Window | Should Be $null
    }
    It 'validates thresholds and provider visibility without saving or calling back' {
        Show-AgentViewSettingsWindow -OnSaved { throw 'Must not run' }
        $ui=(Get-AgentViewSettingsWindowState).Ui
        foreach ($pair in @(@('10','30'),@('91','10'),@('30','4'),@('30.5','10'),@('30','30'))) {
            $ui.Threshold1.Text=$pair[0]; $ui.Threshold2.Text=$pair[1]
            Save-AgentViewSettingsWindow | Should Be $false
            $ui.Error.Visibility | Should Be Visible
        }
        $ui.Threshold1.Text='30'; $ui.Threshold2.Text='10'
        $ui.Claude.IsChecked=$false; $ui.Codex.IsChecked=$false
        Save-AgentViewSettingsWindow | Should Be $false
        $ui.Error.Text | Should Be 'Keep at least one provider visible.'
        Test-Path (Join-Path $env:LOCALAPPDATA 'agent-view/settings.json') | Should Be $false
        Assert-MockCalled Set-AgentViewAutostart -Times 0 -Exactly
    }
    It 'saves edited values before callback, applies autostart, and keeps dock geometry' {
        $s=Get-AgentViewSettings; $s.WidgetEdge='top'; $s.WidgetOffset=32; $s.WidgetScreen='DISPLAY2'; Save-AgentViewSettings $s
        [AppDomain]::CurrentDomain.SetData('settings-test.saved',$null)
        Show-AgentViewSettingsWindow -OnSaved { param($settings)
            [AppDomain]::CurrentDomain.SetData('settings-test.saved',@($settings,(Get-AgentViewSettings)))
        }
        $ui=(Get-AgentViewSettingsWindowState).Ui
        $ui.LangVi.IsChecked=$true; $ui.Refresh60.IsChecked=$true
        $ui.Threshold1.Text='45'; $ui.Threshold2.Text='15'
        $ui.NotifyEnabled.IsChecked=$false; $ui.NotifyReset.IsChecked=$false
        $ui.WidgetEnabled.IsChecked=$true; $ui.Autostart.IsChecked=$true; $ui.Codex.IsChecked=$false
        $ui.Save.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        $saved=[AppDomain]::CurrentDomain.GetData('settings-test.saved')
        $saved.Count | Should Be 2
        foreach ($r in $saved) {
            $r.Language | Should Be vi
            $r.RefreshSeconds | Should Be 60
            $r.NotifyEnabled | Should Be $false
            $r.NotifyReset | Should Be $false
            ($r.NotifyThresholds -join ',') | Should Be '45,15'
            ($r.HiddenProviders -join ',') | Should Be codex
            $r.WidgetEnabled | Should Be $true
            $r.WidgetEdge | Should Be top
            $r.WidgetOffset | Should Be 32
            $r.WidgetScreen | Should Be DISPLAY2
        }
        Assert-MockCalled Set-AgentViewAutostart -Times 1 -Exactly -ParameterFilter { $Enabled -eq $true }
        (Get-AgentViewSettingsWindowState).Window | Should Be $null
    }
    It 'cancels with button and Escape without writing settings' {
        Show-AgentViewSettingsWindow -OnSaved { throw 'Must not run' }
        $ui=(Get-AgentViewSettingsWindowState).Ui
        $ui.Cancel.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        (Get-AgentViewSettingsWindowState).Window | Should Be $null
        Show-AgentViewSettingsWindow
        $w=(Get-AgentViewSettingsWindowState).Window
        $event=New-Object Windows.Input.KeyEventArgs ([Windows.Input.Keyboard]::PrimaryDevice),([Windows.PresentationSource]::FromVisual($w)),0,([Windows.Input.Key]::Escape)
        $event.RoutedEvent=[Windows.Input.Keyboard]::PreviewKeyDownEvent
        $w.RaiseEvent($event)
        (Get-AgentViewSettingsWindowState).Window | Should Be $null
        Test-Path (Join-Path $env:LOCALAPPDATA 'agent-view/settings.json') | Should Be $false
    }
    It 'shows inline save errors and stays open' {
        Mock Save-AgentViewSettings { throw 'disk failure' }
        Show-AgentViewSettingsWindow
        Save-AgentViewSettingsWindow | Should Be $false
        (Get-AgentViewSettingsWindowState).Ui.Error.Text | Should Be 'Could not save settings. Please try again.'
        (Get-AgentViewSettingsWindowState).Window.IsVisible | Should Be $true
    }
    It 'translates visible labels in Vietnamese' {
        Set-AgentViewLanguage vi
        Show-AgentViewSettingsWindow
        $ui=(Get-AgentViewSettingsWindowState).Ui
        $ui.TitleBar.Text | Should Be 'Cài đặt'
        $ui.Save.Content | Should Be 'Lưu'
        $ui.Autostart.Content | Should Be 'Tự chạy khi đăng nhập'
    }
}
