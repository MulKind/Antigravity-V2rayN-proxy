<#
.SYNOPSIS
    Self-contained installer for the Antigravity v2rayn-proxy plugin.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Startup -ReplaceOriginal
#>
[CmdletBinding()]
param(
    [switch]$Startup,
    [switch]$ReplaceOriginal,
    [switch]$NoShortcuts
)
$ErrorActionPreference = 'Stop'

$src  = $PSScriptRoot
$dest = Join-Path $env:USERPROFILE '.gemini\config\plugins\v2rayn-proxy'

Write-Host "Installing Antigravity v2rayn-proxy plugin -> $dest"
if (Test-Path -LiteralPath $dest) {
    # If installing into itself, skip re-copying the root
    if ((Resolve-Path -LiteralPath $src).Path -ine (Resolve-Path -LiteralPath $dest).Path) {
        Remove-Item -LiteralPath $dest -Recurse -Force
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
    }
} else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
}

# Ensure UTF-8 with BOM for PowerShell 5.1 compatibility
$targetRoot = if (Test-Path -LiteralPath $dest) { $dest } else { $src }
$bom = New-Object System.Text.UTF8Encoding($true)
Get-ChildItem -LiteralPath $targetRoot -Recurse -Filter '*.ps1' | ForEach-Object {
    $text = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($_.FullName, $text, $bom)
}
Get-ChildItem -LiteralPath $targetRoot -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

if (-not $NoShortcuts) {
    $args2 = @{}
    if ($Startup)         { $args2.Startup = $true }
    if ($ReplaceOriginal) { $args2.ReplaceOriginal = $true }
    & (Join-Path $targetRoot 'scripts\Install-Launcher.ps1') @args2
}

Write-Host ''
& (Join-Path $targetRoot 'scripts\proxy-status.ps1')
Write-Host ''
Write-Host 'Done. Quit Antigravity completely, then start it from the "Antigravity (Proxy)" shortcut.'
