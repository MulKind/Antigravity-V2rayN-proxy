<#
.SYNOPSIS
    Show V2RayN / proxy status for Antigravity.
.PARAMETER Online
    Also make a real HTTPS request through the proxy (needs network access).
.PARAMETER Json
    Emit machine-readable JSON.
#>
[CmdletBinding()]
param([switch]$Online, [switch]$Json)

. (Join-Path $PSScriptRoot 'lib\ProxyCommon.ps1')

$settings = Get-AgpSettings
$proxy    = Resolve-AgpProxy -Settings $settings
$agExe    = Find-AgpAntigravityPath -Settings $settings
$sys      = Get-AgpSystemProxy
$online   = $null
if ($Online) { $online = Test-AgpProxyOnline -Proxy $proxy -Url $settings.verifyUrl }

$result = [ordered]@{
    v2rayNPath          = $proxy.V2rayNPath
    v2rayNRunning       = $proxy.V2rayNRunning
    v2rayNInboundPort   = $(if ($proxy.Inbound) { $proxy.Inbound.LocalPort } else { $null })
    v2rayNAllowLan      = $(if ($proxy.Inbound) { $proxy.Inbound.AllowLANConn } else { $null })
    proxyUrl            = $proxy.Url
    proxySource         = $proxy.Source
    portListening       = $proxy.Listening
    protocolOk          = $proxy.ProtocolOk
    onlineCheck         = $(if ($online) { '{0}: {1}' -f $online.Ok, $online.Detail } else { 'skipped (use -Online)' })
    windowsSystemProxy  = $(if ($sys) { '{0}:{1} (enabled={2})' -f $sys.Host, $sys.Port, $sys.Enabled } else { 'none' })
    antigravityPath     = $agExe
    antigravityRunning  = (@(Get-Process -Name 'Antigravity' -ErrorAction SilentlyContinue).Count -gt 0)
    currentProcessProxy = $(if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { '(not set)' })
    launchedViaPlugin   = [bool]$env:ANTIGRAVITY_V2RAYN_PROXY
    settingsFile        = $script:AgpSettingsPath
    logFile             = $script:AgpLogPath
}

if ($Json) { ConvertTo-AgpAsciiJson $result; exit 0 }

Write-Host '=== Antigravity V2RayN proxy status ==='
foreach ($k in $result.Keys) { Write-Host ('{0,-20} {1}' -f $k, $result[$k]) }
Write-Host ''
if (-not $proxy.V2rayNPath)      { Write-Host '[!] v2rayN.exe not found -> proxy-config.ps1 -Set v2rayNPath=<path>' }
elseif (-not $proxy.Listening)   { Write-Host '[!] Proxy port is not listening -> start v2rayN (the launcher does this automatically).' }
elseif ($proxy.ProtocolOk -eq $false) { Write-Host '[!] Port is open but is not an HTTP/SOCKS5 proxy -> check proxyPort.' }
else                             { Write-Host '[OK] Proxy endpoint looks healthy.' }
if (-not $env:ANTIGRAVITY_V2RAYN_PROXY) { Write-Host '[i] This process was NOT started by the proxy launcher; use the "Antigravity (Proxy)" shortcut.' }
