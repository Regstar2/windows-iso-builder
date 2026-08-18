#requires -Version 5.1

$modulePath = Join-Path $PSScriptRoot '..\src\WindowsISOBuilder\WindowsISOBuilder.psd1'
Import-Module $modulePath -Force

Describe 'Cache size reporting' {
    InModuleScope WindowsISOBuilder {
        It 'returns zero for a missing directory' {
            $missing = Join-Path $TestDrive 'missing-cache-directory'
            Get-WibDirectorySizeBytes -Path $missing | Should -Be ([int64]0)
        }

        It 'returns zero for an existing empty directory' {
            $empty = Join-Path $TestDrive 'empty-cache-directory'
            New-Item -ItemType Directory -Path $empty -Force | Out-Null

            Get-WibDirectorySizeBytes -Path $empty | Should -Be ([int64]0)
        }

        It 'sums file lengths recursively' {
            $root = Join-Path $TestDrive 'sized-cache-directory'
            $nested = Join-Path $root 'nested'
            New-Item -ItemType Directory -Path $nested -Force | Out-Null

            [IO.File]::WriteAllBytes((Join-Path $root 'one.bin'), [byte[]](1..5))
            [IO.File]::WriteAllBytes((Join-Path $nested 'two.bin'), [byte[]](1..7))

            Get-WibDirectorySizeBytes -Path $root | Should -Be ([int64]12)
        }

        It 'reports an empty cache without throwing' {
            $cache = Join-Path $TestDrive 'cache-root'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null

            $info = Get-WibCacheInfo -CacheDirectory $cache

            $info.TotalBytes | Should -Be ([int64]0)
            @($info.Categories).Count | Should -Be 5
            @($info.Categories | Where-Object { $_.Bytes -ne 0 }).Count | Should -Be 0
        }
    }
}
