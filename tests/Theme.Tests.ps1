. "$PSScriptRoot/../src/Theme.ps1"
Describe 'Bezel theme' {
    It 'matches every product color token' {
        $tokens = Get-Content "$PSScriptRoot/fixtures/theme-tokens.json" -Raw | ConvertFrom-Json
        $theme = Get-AgentViewTheme
        $theme.Count | Should Be 25
        @($tokens.PSObject.Properties).Count | Should Be $theme.Count
        foreach ($key in $theme.Keys) { $tokens.$key | Should Be $theme[$key] }
    }
}

