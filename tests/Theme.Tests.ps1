. "$PSScriptRoot/../src/Theme.ps1"
Describe 'Bezel theme' {
    It 'matches every product color token' {
        $tokens = Get-Content "$PSScriptRoot/fixtures/theme-tokens.json" -Raw | ConvertFrom-Json
        $theme = Get-AgentViewTheme
        $providers = @(Get-AgentProviders)
        $theme.Count | Should Be (23 + $providers.Count)
        foreach ($t in $tokens.PSObject.Properties) { $theme[$t.Name] | Should Be $t.Value }
        foreach ($p in $providers) { $theme[$p.Family] | Should Be $p.Color }
        foreach ($key in $theme.Keys) { (@($tokens.PSObject.Properties.Name) -contains $key -or @($providers.Family) -contains $key) | Should Be $true }
    }
    It 'keeps the Claude and Codex colors used by Ring and Toast' {
        $theme = Get-AgentViewTheme
        $theme['claude'] | Should Be '#E2875C'
        $theme['codex'] | Should Be '#C7CEDA'
    }
}

