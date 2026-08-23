Set-StrictMode -Version Latest

Describe 'Application icon release hardening' {
    BeforeAll {
        $script:IconTestProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:IconTestIconPath = Join-Path $script:IconTestProjectRoot 'src\WindowsISOBuilder.Gui\Assets\WindowsISOBuilder.ico'
        $script:IconTestProjectPath = Join-Path $script:IconTestProjectRoot 'src\WindowsISOBuilder.Gui\WindowsISOBuilder.Gui.csproj'
    }

    It 'tracks a valid bounded multi-size Windows icon asset' {
        Test-Path -LiteralPath $script:IconTestIconPath -PathType Leaf | Should -BeTrue

        $bytes = [IO.File]::ReadAllBytes($script:IconTestIconPath)
        $bytes.Length | Should -BeGreaterThan 1024
        [BitConverter]::ToUInt16($bytes, 0) | Should -Be 0
        [BitConverter]::ToUInt16($bytes, 2) | Should -Be 1

        $count = [int][BitConverter]::ToUInt16($bytes, 4)
        ($count -ge 4) | Should -BeTrue
        (6 + ($count * 16) -le $bytes.Length) | Should -BeTrue

        $widths = @()
        for ($index = 0; $index -lt $count; $index++) {
            $entryOffset = 6 + ($index * 16)
            $width = [int]$bytes[$entryOffset]
            if ($width -eq 0) { $width = 256 }
            $widths += $width

            [uint32]$payloadLength = [BitConverter]::ToUInt32($bytes, $entryOffset + 8)
            [uint32]$payloadOffset = [BitConverter]::ToUInt32($bytes, $entryOffset + 12)
            ($payloadLength -gt 0) | Should -BeTrue
            ($payloadOffset -ge (6 + ($count * 16))) | Should -BeTrue
            ([uint64]$payloadOffset + [uint64]$payloadLength -le [uint64]$bytes.Length) | Should -BeTrue

            $isPng = $payloadLength -ge 8 -and
                $bytes[$payloadOffset] -eq 0x89 -and
                $bytes[$payloadOffset + 1] -eq 0x50 -and
                $bytes[$payloadOffset + 2] -eq 0x4E -and
                $bytes[$payloadOffset + 3] -eq 0x47
            $isDib = $payloadLength -ge 4 -and ([BitConverter]::ToUInt32($bytes, [int]$payloadOffset) -in @(40, 108, 124))
            ($isPng -or $isDib) | Should -BeTrue
        }

        $widths | Should -Contain 16
        $widths | Should -Contain 32
        $widths | Should -Contain 48
        $widths | Should -Contain 256
    }

    It 'uses the icon for the Windows executable and embeds it as a WPF resource' {
        $project = [IO.File]::ReadAllText($script:IconTestProjectPath, [Text.Encoding]::UTF8)
        $project | Should -Match '<ApplicationIcon>Assets\\WindowsISOBuilder\.ico</ApplicationIcon>'
        $project | Should -Match '<Resource Include="Assets\\WindowsISOBuilder\.ico"\s*/>'
    }
}
