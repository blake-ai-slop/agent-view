. "$PSScriptRoot/../src/Ring.ps1"
# Ring.ps1 tự nạp Logos.ps1 thật cùng thư mục.

Describe 'Official provider logos' {
    BeforeEach { [AppDomain]::CurrentDomain.SetData('agent-view.logos', $null) }
    It 'decodes every provider at both embedded sizes as frozen images' {
        foreach ($family in 'claude', 'codex', 'antigravity') {
            foreach ($pair in @(@(14, 48), @(24, 48), @(26, 96), @(60, 96))) {
                $img = Get-AgentViewLogo $family $pair[0]
                ($img -is [System.Windows.Media.ImageSource]) | Should Be $true
                $img.IsFrozen | Should Be $true
                $img.PixelWidth | Should Be $pair[1]
                $img.PixelHeight | Should Be $pair[1]
            }
        }
    }
    It 'caches per family and source size' {
        $a = Get-AgentViewLogo 'claude' 26
        [object]::ReferenceEquals($a, (Get-AgentViewLogo 'Claude' 40)) | Should Be $true
        [object]::ReferenceEquals($a, (Get-AgentViewLogo 'claude' 18)) | Should Be $false
    }
    It 'returns null for unknown or empty families' {
        Get-AgentViewLogo 'zzz' 26 | Should Be $null
        Get-AgentViewLogo '' 26 | Should Be $null
        Get-AgentViewLogoSourceSize 0 | Should Be 96
        Get-AgentViewLogoSourceSize 24 | Should Be 48
        Get-AgentViewLogoSourceSize 25 | Should Be 96
    }
    It 'keeps the embedded file small and records its sources' {
        $path = Join-Path $PSScriptRoot '../src/Logos.ps1'
        (Get-Item $path).Length | Should BeLessThan (150KB)
        $text = [IO.File]::ReadAllText($path)
        $text | Should Match 'https://www\.anthropic\.com/press-kit'
        $text | Should Match 'https://openai\.com/brand/'
        $text | Should Match 'Google-Antigravity-Icon-Full-Color\.png'
        @((Get-AgentViewLogoData).Keys).Count | Should Be 6
    }
}

Describe 'Ring icon uses logos' {
    BeforeEach { [AppDomain]::CurrentDomain.SetData('agent-view.logos', $null) }
    It 'puts the official logo image in the ring center' {
        foreach ($family in 'claude', 'codex', 'antigravity') {
            $ring = New-AgentRing -Size 40 -Stroke 4 -Icon $family -IconSize 18
            ($ring.Tag.Icon -is [System.Windows.Controls.Image]) | Should Be $true
            $ring.Tag.Icon.Width | Should Be 18
            $ring.Tag.Icon.Source.PixelWidth | Should Be 48
        }
    }
    It 'falls back to the drawn icon when a logo is missing and to nothing for unknown ids' {
        Mock Get-AgentViewLogo { $null }
        $ring = New-AgentRing -Size 60 -Stroke 5 -Ticks -Icon claude -IconSize 26
        ($ring.Tag.Icon -is [System.Windows.Controls.Viewbox]) | Should Be $true
        ($ring.Tag.Icon.Child -is [System.Windows.Controls.Canvas]) | Should Be $true
        # Family trong registry nhưng không có logo/hình riêng ⇒ vòng chữ cái đầu màu registry.
        $box = New-AgentRingIcon 'antigravity' 18 (Get-AgentViewTheme)
        $letter = @($box.Child.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] })[0]
        $letter.Text | Should Be 'A'
        $letter.Foreground.Color.ToString() | Should Be '#FF6FA8F5'
        New-AgentRingIcon 'zzz' 18 (Get-AgentViewTheme) | Should Be $null
        (New-AgentRing -Size 40 -Stroke 4 -Icon 'zzz').Tag.Icon | Should Be $null
    }
}
