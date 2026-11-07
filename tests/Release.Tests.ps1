$releaseScript = Join-Path $PSScriptRoot '../tools/release.ps1'
if (-not (Test-Path -LiteralPath $releaseScript)) { return }
. $releaseScript

Describe 'Public release export' {
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $source = Join-Path $caseRoot 'source'
        $target = Join-Path $caseRoot 'public'
        $null = New-Item -ItemType Directory -Force -Path $source,$target
        foreach ($relative in @('src/main.ps1','tests/example.Tests.ps1','tools/parse-check.ps1',
            'install.ps1','uninstall.ps1','README.md','CHANGELOG.md','LICENSE','tools/public.gitignore',
            'design/reference.html','tools/private.ps1','notes/private.txt')) {
            $path = Join-Path $source $relative
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
            [IO.File]::WriteAllText($path, 'safe blake-ai-slop')
        }
        [IO.File]::WriteAllText((Join-Path $source 'src/Version.ps1'), "`$script:AgentViewVersion = '0.1.0'`n")
        [IO.File]::WriteAllText((Join-Path $source 'CHANGELOG.md'), "# Changelog`n`n## v0.1.0`n`n- safe blake-ai-slop`n")
        & git -C $target init --quiet
        & git -C $target config user.name 'Release Tester'
        & git -C $target config user.email ('tester' + '@' + 'example.test')
        Mock Test-ReleaseTheme {}
        Mock Invoke-ReleaseChecks {}
    }
    It 'selects only the allowed paths and substitutes the owner in memory' {
        $files = @(Get-ReleaseFiles $source 'sample-owner')
        $files.Count | Should Be 10
        @($files | Where-Object { $_.Path -eq '.gitignore' }).Count | Should Be 1
        @($files | Where-Object { $_.Path -match 'design|notes|private|public.gitignore' }).Count | Should Be 0
        ($files | Where-Object { $_.Path -eq 'README.md' }).Content | Should Be 'safe sample-owner'
        (Get-Content (Join-Path $source 'README.md') -Raw) | Should Be 'safe blake-ai-slop'
    }
    It 'publishes README PNG images byte for byte and scans only their file names' {
        $blocked = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('Y3Jldw=='))
        $png = [byte[]](@(137,80,78,71,13,10,26,10) + [Text.Encoding]::ASCII.GetBytes($blocked + ' text') + @(0,255,0))
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $source 'docs/images/nested'),(Join-Path $source 'design')
        [IO.File]::WriteAllBytes((Join-Path $source 'docs/images/popup.png'), $png)
        [IO.File]::WriteAllBytes((Join-Path $source 'docs/images/nested/deep.png'), $png)
        [IO.File]::WriteAllBytes((Join-Path $source 'design/shot.png'), $png)
        [IO.File]::WriteAllText((Join-Path $source 'docs/images/notes.txt'), 'safe')
        [IO.File]::WriteAllText((Join-Path $source 'docs/readme-draft.md'), 'safe')
        $files = @(Get-ReleaseFiles $source 'sample-owner')
        @($files | Where-Object { $_.Path -like 'docs/*' } | ForEach-Object Path) -join ',' | Should Be 'docs/images/popup.png'
        $image = $files | Where-Object { $_.Path -eq 'docs/images/popup.png' }
        [Convert]::ToBase64String($image.Bytes) | Should Be ([Convert]::ToBase64String($png))
        @(Test-ReleaseContent @($image)).Count | Should Be 0
        $image.Path = "docs/images/$blocked.png"
        (Test-ReleaseContent @($image) | Out-String) | Should Match "docs/images/$blocked.png: blocked pattern in file name"
        $text = [pscustomobject]@{ Path="src/$blocked-notes.ps1"; Content='safe' }
        @(Test-ReleaseContent @($text)).Count | Should Be 1
        $null = Publish-Release $source '0.1.0' $target 'sample-owner'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $target 'docs/images/popup.png'))) | Should Be ([Convert]::ToBase64String($png))
        Test-Path (Join-Path $target 'docs/images/notes.txt') | Should Be $false
        Test-Path (Join-Path $target 'design') | Should Be $false
    }
    It 'rejects an image file that is not a PNG' {
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $source 'docs/images')
        [IO.File]::WriteAllText((Join-Path $source 'docs/images/fake.png'), 'safe text')
        { Get-ReleaseFiles $source '' } | Should Throw 'Not a PNG file: docs/images/fake.png'
    }
    It 'detects every prohibited expression with file and line information' {
        $samples = @('Y3Jldw==','cGxhbm5lcg==','UmV2','Y29udGV4dC8=','UElURkFMTA==','REVDSVNJT05T','aGVyZHI=','Q3Jld2xpbmU=','aGMgc2VuZA==','Q0xBVURFLm1k','QUdFTlRTLm1k','Q28tQXV0aG9yZWQtQnk=','bm9yZXBseUBhbnRocm9waWM=','R2VuZXJhdGVkIHdpdGg=','bW9ja3Vw','dGFzayBub3Rl','QzpcVXNlcnNcU29tZW9uZQ==','L1VzZXJzL3NvbWVvbmU=','RDpccHJvamVjdA==','dGVzdGVyQGV4YW1wbGUudGVzdA==','MTExMTExMTEtMTExMS0xMTExLTExMTEtMTExMTExMTExMTEx')
        $rules = @(Get-ReleaseRules)
        $samples.Count | Should Be $rules.Count
        for ($i = 0; $i -lt $samples.Count; $i++) {
            $sample = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($samples[$i]))
            $sample | Should Match $rules[$i]
            $file = [pscustomobject]@{ Path='src/sample.ps1'; Content=("safe`n" + $sample) }
            @(Test-ReleaseContent @($file)).Count | Should BeGreaterThan 0
            (Test-ReleaseContent @($file) | Out-String) | Should Match 'src/sample.ps1:2:'
        }
    }
    It 'limits exceptions to exact files and values with a reason' {
        $sample = 'tester' + '@' + 'example.test'
        $file = [pscustomobject]@{ Path='tests/sample.json'; Content=$sample }
        $exception = @{ File='tests/sample.json'; Pattern=('^' + [regex]::Escape($sample) + '$'); Reason='Synthetic value' }
        @(Test-ReleaseContent @($file) @($exception)).Count | Should Be 0
        $file.Path = 'src/sample.json'
        @(Test-ReleaseContent @($file) @($exception)).Count | Should Be 1
        $file.Path = 'tests/sample.json'
        $exception.Reason = ''
        @(Test-ReleaseContent @($file) @($exception)).Count | Should Be 1
        foreach ($known in Get-ReleaseExceptions) {
            $known.File | Should Match '^(tests/fixtures/|install\.ps1$)'
            [string]::IsNullOrWhiteSpace($known.Reason) | Should Be $false
        }
    }
    It 'allows only the fixed toast namespace in the installer' {
        $file = [pscustomobject]@{ Path='install.ps1'; Content=('1AC14E77' + '-02E7-4E5D-B744-' + '2EB1AE5198B7') }
        @(Test-ReleaseContent @($file) (Get-ReleaseExceptions)).Count | Should Be 0
        $file.Path = 'src/Quota.ps1'
        @(Test-ReleaseContent @($file) (Get-ReleaseExceptions)).Count | Should Be 1
        $file.Path = 'install.ps1'; $file.Content = '11111111' + '-1111-1111-1111-' + '111111111111'
        @(Test-ReleaseContent @($file) (Get-ReleaseExceptions)).Count | Should Be 1
    }
    It 'rejects a version that differs from src/Version.ps1 or lacks a changelog section' {
        { Publish-Release $source '0.2.0' $target '' -DryRun } | Should Throw 'does not match src/Version.ps1'
        [IO.File]::WriteAllText((Join-Path $source 'src/Version.ps1'), "`$script:AgentViewVersion = '0.2.0'`n")
        { Publish-Release $source '0.2.0' $target '' -DryRun } | Should Throw "no '## v0.2.0' section"
        Remove-Item -LiteralPath (Join-Path $source 'src/Version.ps1')
        { Publish-Release $source '0.1.0' $target '' -DryRun } | Should Throw 'Missing src/Version.ps1'
        Assert-MockCalled Test-ReleaseTheme -Times 0 -Exactly -Scope It
    }
    It 'matches the repository version and changelog' {
        $repo = Split-Path -Parent $PSScriptRoot
        $text = [IO.File]::ReadAllText((Join-Path $repo 'src/Version.ps1'))
        $version = [regex]::Match($text, "AgentViewVersion\s*=\s*'([^']+)'").Groups[1].Value
        { Test-ReleaseVersion $repo $version } | Should Not Throw
    }
    It 'leaves the target untouched for a dry run and checks the private color reference' {
        $null = Publish-Release $source '0.1.0' $target 'sample-owner' -DryRun
        @(Get-ChildItem -LiteralPath $target -Force | Where-Object { $_.Name -ne '.git' }).Count | Should Be 0
        Assert-MockCalled Test-ReleaseTheme -Times 1 -Exactly -Scope It
        Assert-MockCalled Invoke-ReleaseChecks -Times 0 -Exactly -Scope It
    }
    It 'blocks the entire export before changing the target when scanning fails' {
        $sentinel = Join-Path $target 'keep.txt'
        Set-Content -LiteralPath $sentinel 'keep'
        [IO.File]::WriteAllText((Join-Path $source 'README.md'), ('test' + '@' + 'example.test'))
        { Publish-Release $source '0.1.0' $target '' } | Should Throw
        (Get-Content -LiteralPath $sentinel) | Should Be 'keep'
        @(Get-ChildItem -LiteralPath $target -Force | Where-Object { $_.Name -ne '.git' }).Count | Should Be 1
    }
    It 'requires a configured identity before deleting existing content' {
        & git -C $target config user.name ' '
        Set-Content (Join-Path $target 'keep.txt') 'keep'
        { Publish-Release $source '0.1.0' $target '' } | Should Throw
        Test-Path (Join-Path $target 'keep.txt') | Should Be $true
    }
    It 'exports a fresh commit and tag while preserving the repository' {
        Set-Content (Join-Path $target 'old.txt') 'obsolete'
        & git -C $target config core.autocrlf true
        [IO.File]::WriteAllText((Join-Path $source 'README.md'), "safe blake-ai-slop`n")
        $null = Publish-Release $source '0.1.0' $target 'sample-owner'
        Test-Path (Join-Path $target '.git') | Should Be $true
        Test-Path (Join-Path $target 'old.txt') | Should Be $false
        Test-Path (Join-Path $target 'tools/release.ps1') | Should Be $false
        (& git -C $target log -1 --format=%B | Out-String).Trim() | Should Be 'Release v0.1.0'
        (& git -C $target log -1 --format=%an) | Should Be 'Release Tester'
        (& git -C $target tag --list) | Should Be 'v0.1.0'
        (& git -C $target status --porcelain | Out-String).Trim() | Should Be ''
        Assert-MockCalled Invoke-ReleaseChecks -Times 1 -Exactly -Scope It
        { Publish-Release $source '0.1.0' $target '' } | Should Throw
    }
    It 'does not commit when public verification fails' {
        Mock Invoke-ReleaseChecks { throw 'Verification failed' }
        { Publish-Release $source '0.1.0' $target '' } | Should Throw
        @(& git -C $target tag --list).Count | Should Be 0
    }
}
