. (Join-Path $PSScriptRoot 'Theme.ps1')
. (Join-Path $PSScriptRoot 'Format.ps1')
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,PresentationFramework,PresentationCore,WindowsBase,WindowsFormsIntegration
. (Join-Path $PSScriptRoot 'Popup.ps1')
. (Join-Path $PSScriptRoot 'Widget.ps1')
function Format-QuotaTooltip($Rows) {
    $parts = foreach ($row in $Rows) {
        $name = $row.Name
        if ($row.Provider -eq 'claude') { $name = 'Claude' }
        $remaining = Get-QuotaRemaining $row
        if ($row.Ok -and $null -ne $remaining) { "$name $remaining%" } else { "$name : $($row.Error)" }
    }
    $text = 'agent-view' + "`n" + ($parts -join "`n")
    if ($text.Length -le 63) { return $text }
    $text = $parts -join ' · '
    if ($text.Length -gt 63) { $text = $text.Substring(0, 62); if ([char]::IsHighSurrogate($text[$text.Length-1])) { $text = $text.Substring(0,$text.Length-1) }; $text += '…' }
    return $text
}
function Get-AgentViewStartupPath {
    Join-Path ([Environment]::GetFolderPath('Startup')) 'agent-view.lnk'
}
function Set-AgentViewStartup([bool]$Enabled) {
    $path = Get-AgentViewStartupPath
    if (-not $Enabled) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue; return }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $shortcut.Arguments = '"' + (Join-Path $PSScriptRoot 'launch.vbs') + '"'
    $shortcut.Save()
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
}
function Get-QuotaIconLayout([int]$Size, $Remaining, [switch]$Loading) {
    $spec = switch ($Size) { 16 { @(2,10,9,6.5) } 20 { @(2,12,11,8) } 24 { @(2.5,14,13,10) } default { @(3,19,17,13) } }
    $label = '?'; $index = 2
    if ($null -ne $Remaining) { $label = [string][int]$Remaining; $index = $label.Length }
    $fontSize = $spec[[math]::Min(3,$index)]
    if ($Remaining -eq 100 -and $Size -le 20) { $label = '✓' }
    if ($Loading) { $label = '' }
    [pscustomobject]@{Size=$Size;Stroke=$spec[0];FontSize=$fontSize;Label=$label;RoundCaps=($Size -ge 24)}
}
function Get-QuotaTrayRemaining($Rows) {
    $values = @($Rows | Where-Object { $_.Ok } | ForEach-Object { Get-QuotaRemaining $_ } | Where-Object { $null -ne $_ })
    if ($values.Count -eq 0) { return $null }
    return [int]($values | Measure-Object -Minimum).Minimum
}
function New-QuotaIconBitmap($Rows, [int]$Size = 16, [switch]$Loading, [int]$Frame = 0) {
    $remaining = Get-QuotaTrayRemaining $Rows
    $level = Get-QuotaLevel $remaining
    $theme = Get-AgentViewTheme
    $layout = Get-QuotaIconLayout $Size $remaining -Loading:$Loading
    $bitmap = New-Object Drawing.Bitmap $Size,$Size
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $resources = New-Object 'System.Collections.Generic.List[System.IDisposable]'
    try {
        $graphics.SmoothingMode = 'AntiAlias'; $graphics.TextRenderingHint = 'AntiAliasGridFit'
        $graphics.Clear([Drawing.Color]::Transparent)
        $disc = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($theme['tray-disc'])); $resources.Add($disc)
        $graphics.FillEllipse($disc,0,0,$Size,$Size)
        $trackColor = $theme['tray-track']; if ($null -eq $remaining -or $Loading) { $trackColor = '#5A6274' }
        $track = New-Object Drawing.Pen ([Drawing.ColorTranslator]::FromHtml($trackColor)),([single]$layout.Stroke); $resources.Add($track)
        $inset = [single]($layout.Stroke/2); $diameter = [single]($Size-$layout.Stroke)
        $graphics.DrawEllipse($track,$inset,$inset,$diameter,$diameter)
        if ($Loading -or ($null -ne $remaining -and $remaining -gt 0)) {
            $color = $theme[$level]; $alpha = 255; $start = -90; $sweep = 3.6*$remaining
            if ($Loading) { $color=$theme['unk-hi']; $start += ($Frame%8)*45; $sweep=90 }
            elseif ($level -eq 'crit') { $alpha = [int](255*@(1,.75,.45,.75)[$Frame%4]) }
            $arc = New-Object Drawing.Pen ([Drawing.Color]::FromArgb($alpha,[Drawing.ColorTranslator]::FromHtml($color))),([single]$layout.Stroke); $resources.Add($arc)
            if ($layout.RoundCaps) { $arc.StartCap='Round'; $arc.EndCap='Round' }
            $graphics.DrawArc($arc,$inset,$inset,$diameter,$diameter,[single]$start,[single]$sweep)
        }
        if ($layout.Label -eq '✓') {
            $pen = New-Object Drawing.Pen ([Drawing.ColorTranslator]::FromHtml('#F4F6FA')),([single]($Size*.1125)); $resources.Add($pen)
            $pen.StartCap='Round'; $pen.EndCap='Round'; $pen.LineJoin='Round'
            $graphics.DrawLines($pen,[Drawing.PointF[]]@((New-Object Drawing.PointF ($Size*.31),($Size*.52)),(New-Object Drawing.PointF ($Size*.45),($Size*.65)),(New-Object Drawing.PointF ($Size*.70),($Size*.37))))
        } elseif ($layout.Label) {
            $font = New-Object Drawing.Font 'Segoe UI',([single]$layout.FontSize),([Drawing.FontStyle]::Bold),([Drawing.GraphicsUnit]::Pixel); $resources.Add($font)
            $color = '#F4F6FA'; if ($null -eq $remaining) { $color='#B8BFCC' }
            $brush = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($color)); $resources.Add($brush)
            $format = [Drawing.StringFormat]::GenericTypographic.Clone(); $resources.Add($format); $format.Alignment='Center'
            # GDI+ line box includes ascent/descent padding; place it manually around the centre.
            $height = $font.GetHeight($graphics)
            $graphics.DrawString($layout.Label,$font,$brush,[single]($Size/2),[single](($Size-$height)/2-.3),$format)
        }
        # Bitmap is one disposable value, not a list of quota rows.
        return ,$bitmap
    } catch { $bitmap.Dispose(); throw }
    finally { foreach ($resource in $resources) { $resource.Dispose() }; $graphics.Dispose() }
}
function New-QuotaIcon($Rows, [switch]$Loading, [int]$Frame = 0) {
    $size = [Windows.Forms.SystemInformation]::SmallIconSize.Width
    $bitmap = New-QuotaIconBitmap $Rows -Size $size -Loading:$Loading -Frame $Frame
    $handle = [IntPtr]::Zero
    try {
        $handle=$bitmap.GetHicon(); $borrowed=[Drawing.Icon]::FromHandle($handle)
        try { return $borrowed.Clone() } finally { $borrowed.Dispose() }
    } finally {
        if ($handle -ne [IntPtr]::Zero) { [void][AgentView.Native]::DestroyIcon($handle) }
        $bitmap.Dispose()
    }
}
function Start-AgentView {
    if (-not ('AgentView.Native' -as [type])) { Add-Type 'namespace AgentView { public static class Native { [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h); } }' }
    $state = @{ Rows=@(); Worker=$null; Pending=$null; Last=[datetime]::MinValue; Frame=0; Loading=$false }
    $context = New-Object Windows.Forms.ApplicationContext
    $notify = New-Object Windows.Forms.NotifyIcon
    $menu = New-Object Windows.Forms.ContextMenuStrip
    $refresh = $menu.Items.Add('Làm mới')
    $widget = $menu.Items.Add('Widget nổi'); $widget.CheckOnClick=$true; $widget.Checked=(Get-AgentViewWidgetState).Settings.WidgetEnabled
    $startup = $menu.Items.Add('Tự chạy khi đăng nhập'); $startup.CheckOnClick = $true; $startup.Checked = Test-Path (Get-AgentViewStartupPath)
    $exit = $menu.Items.Add('Thoát')
    $notify.ContextMenuStrip = $menu; $notify.Icon = New-QuotaIcon @(); $notify.Text = 'Đang cập nhật quota'; $notify.Visible = $true
    $animation = New-Object Windows.Forms.Timer
    $animation.Add_Tick({
        $state.Frame++
        $old=$notify.Icon; $notify.Icon=New-QuotaIcon $state.Rows -Loading:$state.Loading -Frame $state.Frame; $old.Dispose()
    }.GetNewClosure())
    $begin = {
        if ($null -ne $state.Worker) { return }
        $state.Loading=$true; $state.Frame=0; $animation.Interval=125; $animation.Start()
        if (Get-Command Update-AgentViewPopup -ErrorAction SilentlyContinue) { Update-AgentViewPopup -Rows $state.Rows -Loading }
        Update-AgentViewWidget -Rows $state.Rows -Loading
        $state.Worker = [PowerShell]::Create()
        [void]$state.Worker.AddScript({ param($path)
            try {
                if (-not (Test-Path -LiteralPath $path)) { throw 'Thiếu Quota.ps1' }
                . $path
                Get-AgentQuotas
            } catch {
                $errorText = 'Không đọc được quota'; if (-not (Test-Path -LiteralPath $path)) { $errorText = 'Thiếu Quota.ps1' }
                foreach ($provider in @('claude','codex')) {
                    $providerName = 'Claude Code'; if ($provider -eq 'codex') { $providerName = 'Codex' }
                    [pscustomobject]@{Provider=$provider;Name=$providerName;Ok=$false;Error=$errorText;FiveHourUsed=$null;WeekUsed=$null;FiveHourResetsAt=$null;WeekResetsAt=$null;FetchedAt=Get-Date} }
            }
        }).AddArgument((Join-Path $PSScriptRoot 'Quota.ps1'))
        $state.Pending = $state.Worker.BeginInvoke(); $state.Last = Get-Date
    }.GetNewClosure()
    $openPopup = {
        $retry = { param($provider) & $begin }.GetNewClosure()
        Show-AgentViewPopup -Rows $state.Rows -Loading:$state.Loading -OnRefresh $begin -OnRetry $retry
    }.GetNewClosure()
    $widget.Add_Click({
        $s=Get-AgentViewWidgetState; $s.Settings.WidgetEnabled=$this.Checked
        if($this.Checked){Show-AgentViewWidget -Rows $state.Rows -Loading:$state.Loading -OnOpenPopup $openPopup}else{Hide-AgentViewWidget}
        Save-AgentViewSettings $s.Settings
    }.GetNewClosure())
    if($widget.Checked){Show-AgentViewWidget -Rows $state.Rows -OnOpenPopup $openPopup}
    $refresh.Add_Click($begin)
    $startup.Add_Click({ Set-AgentViewStartup $this.Checked })
    $exit.Add_Click({ $context.ExitThread() }.GetNewClosure())
    $notify.Add_MouseClick({ if ($_.Button -eq [Windows.Forms.MouseButtons]::Left) {
        $retry = { param($provider) & $begin }.GetNewClosure()
        Show-AgentViewPopup -Rows $state.Rows -Loading:$state.Loading -OnRefresh $begin -OnRetry $retry
    } }.GetNewClosure())
    $timer = New-Object Windows.Forms.Timer; $timer.Interval = 250
    $timer.Add_Tick({
        if ($state.Worker -and $state.Pending.IsCompleted) {
            try { $state.Rows = @(ConvertTo-QuotaRows ($state.Worker.EndInvoke($state.Pending))) } finally { $state.Worker.Dispose(); $state.Worker=$null }
            $state.Loading=$false; $state.Frame=0; $animation.Stop()
            if ((Get-QuotaLevel (Get-QuotaTrayRemaining $state.Rows)) -eq 'crit') { $animation.Interval=400; $animation.Start() }
            if (Get-Command Update-AgentViewPopup -ErrorAction SilentlyContinue) { Update-AgentViewPopup -Rows $state.Rows }
            Update-AgentViewWidget -Rows $state.Rows
            $old = $notify.Icon; $notify.Icon = New-QuotaIcon $state.Rows; $old.Dispose()
            $notify.Text = Format-QuotaTooltip $state.Rows
        }
        if (-not $state.Worker -and ((Get-Date)-$state.Last).TotalSeconds -ge 120) { & $begin }
    }.GetNewClosure())
    try { & $begin; $timer.Start(); [Windows.Forms.Application]::Run($context) }
    finally {
        $timer.Stop(); $timer.Dispose(); $animation.Stop(); $animation.Dispose()
        if (Get-Command Hide-AgentViewPopup -ErrorAction SilentlyContinue) { Hide-AgentViewPopup }
        Hide-AgentViewWidget
        if ($state.Worker) { $state.Worker.Stop(); $state.Worker.Dispose() }
        $notify.Visible=$false; $notify.Icon.Dispose(); $notify.Dispose(); $menu.Dispose(); $context.Dispose()
    }
}
