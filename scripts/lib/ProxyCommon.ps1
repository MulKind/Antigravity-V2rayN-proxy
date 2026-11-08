# ProxyCommon.ps1 - shared helpers for the v2rayn-proxy plugin.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.
# Dot-source this file:  . "$PSScriptRoot\lib\ProxyCommon.ps1"

$script:AgpDataDir      = Join-Path $env:LOCALAPPDATA 'AntigravityProxy'
$script:AgpSettingsPath = Join-Path $script:AgpDataDir 'settings.json'
$script:AgpLogPath      = Join-Path $script:AgpDataDir 'launcher.log'
$script:AgpTitle        = 'Antigravity Proxy (V2RayN)'

# ---------------------------------------------------------------- settings

function Get-AgpDefaultSettings {
    $s = [ordered]@{}
    $s.v2rayNPath         = ''          # empty = auto detect
    $s.antigravityPath    = ''          # empty = auto detect
    $s.proxyHost          = '127.0.0.1'
    $s.proxyPort          = 0           # 0 = read from v2rayN guiConfigs\guiNConfig.json
    $s.proxyScheme        = 'auto'      # auto | http | socks5
    $s.autoStartV2rayN    = $true       # start v2rayN when the proxy port is not listening
    $s.waitTimeoutSec     = 30          # how long to wait for v2rayN to open its port
    $s.onProxyFailure     = 'ask'       # ask | continue | abort
    $s.verifyBeforeLaunch = $false      # do a real HTTPS request through the proxy before launch
    $s.verifyUrl          = 'https://www.google.com/generate_204'
    $s.noProxy            = 'localhost,127.0.0.1,::1,.local'
    $s.setElectronFlags   = $true       # pass --proxy-server to Antigravity.exe
    $s.sessionCheck       = 'warn'      # warn | off  (SessionStart hook behaviour)
    return $s
}

function Get-AgpSettings {
    $s = Get-AgpDefaultSettings
    if (Test-Path -LiteralPath $script:AgpSettingsPath) {
        try {
            $j = Get-Content -LiteralPath $script:AgpSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) {
                if ($s.Contains($p.Name)) { $s[$p.Name] = $p.Value }
            }
        } catch {
            Write-AgpLog "settings.json is invalid, using defaults: $($_.Exception.Message)"
        }
    }
    return $s
}

function Save-AgpSettings {
    param([System.Collections.IDictionary]$Settings)
    if (-not (Test-Path -LiteralPath $script:AgpDataDir)) {
        New-Item -ItemType Directory -Path $script:AgpDataDir -Force | Out-Null
    }
    $json = New-Object PSObject -Property $Settings | Select-Object @($Settings.Keys) | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($script:AgpSettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-AgpLog {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $script:AgpDataDir)) {
            New-Item -ItemType Directory -Path $script:AgpDataDir -Force | Out-Null
        }
        if ((Test-Path -LiteralPath $script:AgpLogPath) -and ((Get-Item -LiteralPath $script:AgpLogPath).Length -gt 512KB)) {
            Move-Item -LiteralPath $script:AgpLogPath -Destination ($script:AgpLogPath + '.old') -Force
        }
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $script:AgpLogPath -Value $line -Encoding UTF8
    } catch { }
}

function Show-AgpPopup {
    # Flags: 16=error 32=question 48=warning 64=info, +4 = Yes/No buttons.
    # Returns 6=Yes 7=No 1=OK -1=timeout.
    param([string]$Text, [int]$Flags = 64, [int]$TimeoutSec = 0)
    try {
        $sh = New-Object -ComObject WScript.Shell
        return $sh.Popup($Text, $TimeoutSec, $script:AgpTitle, $Flags)
    } catch {
        Write-Host $Text
        return -1
    }
}

# ---------------------------------------------------------------- discovery

function Get-AgpShortcutTarget {
    param([string]$NamePattern)
    $dirs = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    )
    $shell = New-Object -ComObject WScript.Shell
    foreach ($d in $dirs) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
        $links = Get-ChildItem -LiteralPath $d -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
                 Where-Object { $_.BaseName -match $NamePattern }
        foreach ($l in $links) {
            $t = $shell.CreateShortcut($l.FullName).TargetPath
            if ($t -and $t.ToLower().EndsWith('.exe') -and (Test-Path -LiteralPath $t)) { return $t }
        }
    }
    return $null
}

function Find-AgpV2rayNPath {
    param([System.Collections.IDictionary]$Settings)
    if ($Settings -and $Settings.v2rayNPath -and (Test-Path -LiteralPath $Settings.v2rayNPath)) {
        return (Resolve-Path -LiteralPath $Settings.v2rayNPath).Path
    }
    $p = Get-Process -Name 'v2rayN' -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
    if ($p) { return $p.Path }

    $t = Get-AgpShortcutTarget -NamePattern '^v2rayN'
    if ($t -and ([System.IO.Path]::GetFileName($t) -ieq 'v2rayN.exe')) { return $t }

    $roots = @()
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -eq 'Fixed' -and $drive.IsReady) { $roots += $drive.RootDirectory.FullName }
    }
    $roots += @($env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs'), $env:USERPROFILE,
                (Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'Downloads'),
                (Join-Path $env:USERPROFILE 'scoop\apps'))
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'v2rayN' }
        foreach ($d in $dirs) {
            foreach ($cand in @((Join-Path $d.FullName 'v2rayN.exe'),
                                (Join-Path $d.FullName 'current\v2rayN.exe'),
                                (Join-Path (Join-Path $d.FullName $d.Name) 'v2rayN.exe'))) {
                if (Test-Path -LiteralPath $cand) { return $cand }
            }
        }
    }
    return $null
}

function Get-AgpV2rayNInbound {
    # Reads <v2rayN dir>\guiConfigs\guiNConfig.json and returns the first inbound.
    param([string]$V2rayNPath)
    if (-not $V2rayNPath) { return $null }
    $dir = Split-Path -Parent $V2rayNPath
    foreach ($cfg in @((Join-Path $dir 'guiConfigs\guiNConfig.json'), (Join-Path $dir 'guiNConfig.json'))) {
        if (-not (Test-Path -LiteralPath $cfg)) { continue }
        try {
            $j = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
            $inb = $null
            if ($j.PSObject.Properties['Inbound'])      { $inb = @($j.Inbound)[0] }
            elseif ($j.PSObject.Properties['inbound'])  { $inb = @($j.inbound)[0] }
            if ($inb -and $inb.LocalPort) {
                return [pscustomobject]@{
                    LocalPort    = [int]$inb.LocalPort
                    Protocol     = [string]$inb.Protocol
                    AllowLANConn = [bool]$inb.AllowLANConn
                    User         = [string]$inb.User
                    Pass         = [string]$inb.Pass
                    ConfigPath   = $cfg
                }
            }
        } catch { Write-AgpLog "cannot parse ${cfg}: $($_.Exception.Message)" }
    }
    return $null
}

function Get-AgpSystemProxy {
    try {
        $k = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $server = [string]$k.ProxyServer
        if ($server -match '(?:^|=)(?<h>[\w\.\-]+):(?<p>\d+)') {
            return [pscustomobject]@{ Host = $Matches['h']; Port = [int]$Matches['p']; Enabled = ($k.ProxyEnable -eq 1) }
        }
    } catch { }
    return $null
}

function Find-AgpAntigravityPath {
    param([System.Collections.IDictionary]$Settings)
    if ($Settings -and $Settings.antigravityPath -and (Test-Path -LiteralPath $Settings.antigravityPath)) {
        return (Resolve-Path -LiteralPath $Settings.antigravityPath).Path
    }
    foreach ($cand in @((Join-Path $env:LOCALAPPDATA 'Programs\antigravity\Antigravity.exe'),
                        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\Antigravity.exe'),
                        (Join-Path $env:ProgramFiles 'Antigravity\Antigravity.exe'))) {
        if (Test-Path -LiteralPath $cand) { return $cand }
    }
    $p = Get-Process -Name 'Antigravity' -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
    if ($p) { return $p.Path }
    $t = Get-AgpShortcutTarget -NamePattern '^Antigravity$'
    if ($t) { return $t }
    return $null
}

# ---------------------------------------------------------------- probing

function Test-AgpTcpPort {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 500)
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $c.EndConnect($ar)
        return $true
    } catch { return $false } finally { $c.Close() }
}

function Test-AgpHttpProxy {
    # Sends an HTTP CONNECT. Returns the HTTP status code, or $null if the port
    # does not speak HTTP proxy.
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 2000, [string]$Target = 'www.google.com:443')
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $null }
        $c.EndConnect($ar)
        $c.ReceiveTimeout = $TimeoutMs; $c.SendTimeout = $TimeoutMs
        $s = $c.GetStream()
        $req = [System.Text.Encoding]::ASCII.GetBytes("CONNECT $Target HTTP/1.1`r`nHost: $Target`r`nProxy-Connection: close`r`n`r`n")
        $s.Write($req, 0, $req.Length)
        $buf = New-Object byte[] 512
        $n = $s.Read($buf, 0, $buf.Length)
        if ($n -le 0) { return $null }
        $line = ([System.Text.Encoding]::ASCII.GetString($buf, 0, $n) -split "`r?`n")[0]
        if ($line -match '^HTTP/1\.[01] (\d{3})') { return [int]$Matches[1] }
        return $null
    } catch { return $null } finally { $c.Close() }
}

function Test-AgpSocks5 {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 1500)
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $c.EndConnect($ar)
        $c.ReceiveTimeout = $TimeoutMs; $c.SendTimeout = $TimeoutMs
        $s = $c.GetStream()
        $hello = [byte[]](5, 1, 0)
        $s.Write($hello, 0, 3)
        $buf = New-Object byte[] 2
        $n = $s.Read($buf, 0, 2)
        return ($n -eq 2 -and $buf[0] -eq 5 -and $buf[1] -eq 0)
    } catch { return $false } finally { $c.Close() }
}

function Resolve-AgpProxy {
    # Works out which proxy endpoint to use.
    # -Quick: only a TCP check, no protocol probing (used by the session hook).
    param([System.Collections.IDictionary]$Settings, [switch]$Quick)
    if (-not $Settings) { $Settings = Get-AgpSettings }

    $v2Path   = Find-AgpV2rayNPath -Settings $Settings
    $inbound  = Get-AgpV2rayNInbound -V2rayNPath $v2Path
    $v2Proc   = Get-Process -Name 'v2rayN' -ErrorAction SilentlyContinue | Select-Object -First 1
    $hostName = [string]$Settings.proxyHost
    if (-not $hostName) { $hostName = '127.0.0.1' }

    $port = [int]$Settings.proxyPort; $source = 'settings.json'
    if ($port -le 0 -and $inbound) { $port = $inbound.LocalPort; $source = 'v2rayN guiNConfig.json' }
    if ($port -le 0) {
        $sys = Get-AgpSystemProxy
        if ($sys -and ($sys.Host -match '^(127\.|localhost)')) { $port = $sys.Port; $source = 'Windows system proxy' }
    }
    if ($port -le 0) { $port = 10808; $source = 'default (10808)' }

    $scheme = ([string]$Settings.proxyScheme).ToLower()
    $listening = Test-AgpTcpPort -HostName $hostName -Port $port -TimeoutMs 400
    $finalPort = $port
    $protocolOk = $null

    if (-not $Quick -and $listening) {
        if ($scheme -eq 'auto' -or $scheme -eq 'http') {
            $code = Test-AgpHttpProxy -HostName $hostName -Port $port
            if ($code) { $scheme = 'http'; $protocolOk = $true }
            elseif (Test-AgpTcpPort -HostName $hostName -Port ($port + 1) -TimeoutMs 400) {
                # v2rayN 6.x style: socks on N, http on N+1
                $code = Test-AgpHttpProxy -HostName $hostName -Port ($port + 1)
                if ($code) { $scheme = 'http'; $finalPort = $port + 1; $protocolOk = $true }
            }
        }
        if ($protocolOk -ne $true -and ($scheme -eq 'auto' -or $scheme -eq 'socks5')) {
            if (Test-AgpSocks5 -HostName $hostName -Port $port) { $scheme = 'socks5'; $protocolOk = $true }
        }
        if ($protocolOk -ne $true) { $protocolOk = $false }
    }
    if ($scheme -eq 'auto') { $scheme = 'http' }   # v2rayN 7.x mixed inbound accepts HTTP

    $authPart = ''
    if ($inbound -and $inbound.User -and $inbound.Pass -and $source -ne 'settings.json') {
        $authPart = '{0}:{1}@' -f [uri]::EscapeDataString($inbound.User), [uri]::EscapeDataString($inbound.Pass)
    }

    return [pscustomobject]@{
        Host          = $hostName
        Port          = $finalPort
        Scheme        = $scheme
        Url           = '{0}://{1}{2}:{3}' -f $scheme, $authPart, $hostName, $finalPort
        ElectronUrl   = '{0}://{1}:{2}' -f $scheme, $hostName, $finalPort
        Source        = $source
        Listening     = $listening
        ProtocolOk    = $protocolOk
        V2rayNPath    = $v2Path
        V2rayNRunning = [bool]$v2Proc
        Inbound       = $inbound
    }
}

function Test-AgpProxyOnline {
    # Real HTTPS request through the proxy. Returns $true/$false (+ message via -Detail).
    param([pscustomobject]$Proxy, [string]$Url = 'https://www.google.com/generate_204', [int]$TimeoutSec = 8)
    if ($Proxy.Scheme -ne 'http') {
        return [pscustomobject]@{ Ok = $null; Detail = 'online check only supports http proxies' }
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-WebRequest -Uri $Url -Proxy ('http://{0}:{1}' -f $Proxy.Host, $Proxy.Port) -UseBasicParsing -TimeoutSec $TimeoutSec -Method Get
        $sw.Stop()
        return [pscustomobject]@{ Ok = $true; Detail = ('HTTP {0} in {1} ms' -f [int]$r.StatusCode, $sw.ElapsedMilliseconds) }
    } catch {
        return [pscustomobject]@{ Ok = $false; Detail = $_.Exception.Message }
    }
}

function Set-AgpProxyEnvironment {
    # Sets proxy env vars on the current process (children inherit them).
    param([pscustomobject]$Proxy, [string]$NoProxy)
    $env:HTTP_PROXY  = $Proxy.Url
    $env:HTTPS_PROXY = $Proxy.Url
    $env:ALL_PROXY   = $Proxy.Url
    $env:NO_PROXY    = $NoProxy
    $env:ANTIGRAVITY_V2RAYN_PROXY = $Proxy.Url   # marker read by the session hook
}

function ConvertTo-AgpAsciiJson {
    # PowerShell 5.1 does not escape non-ASCII; escape it so stdout encoding cannot corrupt it.
    param($InputObject)
    $json = $InputObject | ConvertTo-Json -Depth 10 -Compress
    return [regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
}
