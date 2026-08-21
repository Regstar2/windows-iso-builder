Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$iconPath = Join-Path $root 'src\WindowsISOBuilder.Gui\Assets\WindowsISOBuilder.ico'
$projectPath = Join-Path $root 'src\WindowsISOBuilder.Gui\WindowsISOBuilder.Gui.csproj'

Describe 'Application icon release hardening' {
    It 'tracks a valid multi-size Windows icon asset' {
        Test-Path -LiteralPath $iconPath -PathType Leaf | Should -BeTrue

        $bytes = [IO.File]::ReadAllBytes($iconPath)
        $bytes.Length | Should -BeGreaterThan 1024
        [BitConverter]::ToUInt16($bytes, 0) | Should -Be 0
        [BitConverter]::ToUInt16($bytes, 2) | Should -Be 1

        $count = [int][BitConverter]::ToUInt16($bytes, 4)
        ($count -ge 3) | Should -BeTrue

        $widths = @()
        for ($index = 0; $index -lt $count; $index++) {
            $width = [int]$bytes[6 + ($index * 16)]
            if ($width -eq 0) { $width = 256 }
            $widths += $width
        }

        $widths | Should -Contain 16
        $widths | Should -Contain 32
        $widths | Should -Contain 48
    }

    It 'uses the icon for the Windows executable and embeds it as a WPF resource' {
        $project = [IO.File]::ReadAllText($projectPath, [Text.Encoding]::UTF8)
        $project | Should -Match '<ApplicationIcon>Assets\\WindowsISOBuilder\.ico</ApplicationIcon>'
        $project | Should -Match '<Resource Include="Assets\\WindowsISOBuilder\.ico"\s*/>'
    }
}
