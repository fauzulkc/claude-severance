# Unit tests for src\Severance.psm1 (Pester 5). Nothing here touches the real install: every test that writes files
# points LOCALAPPDATA at Pester's TestDrive first.
#   Invoke-Pester -Path tests
BeforeAll {
    $script:Module = Join-Path $PSScriptRoot '..\src\Severance.psm1'
    Import-Module $script:Module -Force
    $script:RealLocal = $env:LOCALAPPDATA
}
AfterAll { $env:LOCALAPPDATA = $script:RealLocal }

Describe 'New-AccountLabel' {
    It 'takes the first letter or digit of <Name>' -ForEach @(
        @{ Name = 'Acme'; Want = 'A' }, @{ Name = 'acme corp'; Want = 'A' }, @{ Name = '  9lives'; Want = '9' },
        @{ Name = '--x'; Want = 'X' }, @{ Name = '---'; Want = '?' }, @{ Name = ''; Want = '?' }
    ) { New-AccountLabel $Name | Should -BeExactly $Want }
}

Describe 'New-AccountId' {
    It 'makes a lowercase slug' { New-AccountId 'Acme Corp!' @() | Should -BeExactly 'acme-corp' }
    It 'numbers a clash' { New-AccountId 'Acme' @('acme', 'acme2') | Should -BeExactly 'acme3' }
    It 'never returns auto or empty' {
        New-AccountId 'auto' @() | Should -BeExactly 'account'
        New-AccountId '!!!' @() | Should -BeExactly 'account'
    }
}

Describe 'Account aliases' {
    BeforeAll {
        $script:Others = @(
            [pscustomobject]@{ id = 'personal'; name = 'Personal'; alias = '' },
            [pscustomobject]@{ id = 'acme'; name = 'Acme'; alias = 'acme-cc' }
        )
    }
    It 'defaults to claude-<id>' { Get-AccountAlias ([pscustomobject]@{ id = 'globex' }) | Should -BeExactly 'claude-globex' }
    It 'keeps a stored alias, lowercased' { Get-AccountAlias ([pscustomobject]@{ id = 'globex'; alias = 'GX' }) | Should -BeExactly 'gx' }
    It 'accepts a free name' { Test-SeveranceAlias 'claude-globex-test-zz9' 'globex' $Others | Should -BeNullOrEmpty }
    It 'refuses <Alias>: <Why>' -ForEach @(
        @{ Alias = ''; Why = 'command name' }
        @{ Alias = 'work 2'; Why = 'letters, digits' }
        @{ Alias = '-x'; Why = 'letters, digits' }
        @{ Alias = 'glx.cmd'; Why = 'extension' }
        @{ Alias = 'claude'; Why = 'taken by Windows or Claude' }
        @{ Alias = 'dir'; Why = 'taken by Windows or Claude' }
        @{ Alias = 'acme-cc'; Why = 'command for Acme' }
        @{ Alias = 'ac'; Why = 'PowerShell alias' }
        @{ Alias = 'claude-personal'; Why = 'command for Personal' }
        @{ Alias = 'notepad'; Why = 'already a command on this PC' }
        @{ Alias = 'ls'; Why = 'PowerShell alias' }
    ) { Test-SeveranceAlias $Alias 'globex' $Others | Should -Match ([regex]::Escape($Why)) }
    It 'does not clash an account with itself' { Test-SeveranceAlias 'acme-cc' 'acme' $Others | Should -BeNullOrEmpty }
}

Describe 'Read-OAuthAccount' {
    It 'reads email and org from a file whose keys differ only by case' {
        $f = Join-Path $TestDrive 'state.json'
        Set-Content $f '{"projects":{"D:/Code":{},"d:/code":{}},"oauthAccount":{"emailAddress":"you@acme.example","organizationName":"Acme"}}'
        $a = Read-OAuthAccount $f
        $a['emailAddress'] | Should -BeExactly 'you@acme.example'
        $a['organizationName'] | Should -BeExactly 'Acme'
    }
    It 'returns nothing when signed out or the file is missing' {
        $f = Join-Path $TestDrive 'empty.json'
        Set-Content $f '{"projects":{}}'
        Read-OAuthAccount $f | Should -BeNullOrEmpty
        Read-OAuthAccount (Join-Path $TestDrive 'nope.json') | Should -BeNullOrEmpty
    }
}

Describe 'Logos and icons' {
    BeforeAll {
        $env:LOCALAPPDATA = Join-Path $TestDrive 'local'
        $script:Png = Join-Path $PSScriptRoot '..\assets\logo\png\mark-256.png'
        $script:Ico = Join-Path $PSScriptRoot '..\src\assets\severance.ico'
    }
    It 'keeps logos inside the sandbox' { Get-SeveranceLogoDir | Should -BeLike "$TestDrive*" }
    It 'imports a PNG as logos\<id>.png' {
        Import-SeveranceLogo $Png 'acme' | Should -BeExactly 'acme.png'
        Join-Path (Get-SeveranceLogoDir) 'acme.png' | Should -Exist
        Get-SeveranceLogoPath ([pscustomobject]@{ logo = 'acme.png' }) | Should -Exist
    }
    It 'imports an ICO with PNG-compressed frames' { Import-SeveranceLogo $Ico 'globex' | Should -BeExactly 'globex.png' }
    It 'refuses a file that is not an image' { { Import-SeveranceLogo (Join-Path $PSScriptRoot '..\README.md') 'x' } | Should -Throw '*use a*' }
    It 'refuses a missing file' { { Import-SeveranceLogo (Join-Path $TestDrive 'gone.png') 'x' } | Should -Throw "*isn't there*" }
    It 'builds an icon from a logo, and from a letter when the logo is unusable' {
        $a = Join-Path $TestDrive 'a.ico'; $b = Join-Path $TestDrive 'b.ico'
        New-SeveranceIcon $a '#C08A2E' 'A' (Get-SeveranceLogoPath ([pscustomobject]@{ logo = 'acme.png' }))
        New-SeveranceIcon $b '#C08A2E' 'A' (Join-Path $PSScriptRoot '..\README.md')
        foreach ($f in $a, $b) {
            $bytes = [IO.File]::ReadAllBytes($f)
            [BitConverter]::ToUInt16($bytes, 2) | Should -Be 1    # an icon file
            [BitConverter]::ToUInt16($bytes, 4) | Should -Be 1    # one frame
        }
    }
}

Describe 'Config checks' {
    It 'needs exactly one main account' {
        { Test-SeveranceConfig ([pscustomobject]@{ accounts = @([pscustomobject]@{ id = 'a'; main = $false }) }) } | Should -Throw '*main*'
    }
    It 'refuses a bad id' {
        { Test-SeveranceConfig ([pscustomobject]@{ accounts = @([pscustomobject]@{ id = 'Bad Id'; main = $true }) }) } | Should -Throw '*invalid*'
    }
    It 'refuses duplicate ids' {
        $c = [pscustomobject]@{ accounts = @([pscustomobject]@{ id = 'a'; main = $true }, [pscustomobject]@{ id = 'a'; main = $false }) }
        { Test-SeveranceConfig $c } | Should -Throw '*unique*'
    }
}

Describe 'Version' {
    It 'is semantic' { Get-SeveranceVersion | Should -Match '^\d+\.\d+\.\d+$' }
    It 'has a CHANGELOG section' {
        $log = Get-Content (Join-Path $PSScriptRoot '..\CHANGELOG.md') -Raw
        $log | Should -Match ([regex]::Escape("## [$(Get-SeveranceVersion)]"))
    }
}
