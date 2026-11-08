# SessionStart hook for the v2rayn-proxy plugin.
# Must be fast and must ALWAYS print a JSON object on stdout.
$ErrorActionPreference = 'SilentlyContinue'
$out = @{}
try {
    . (Join-Path $PSScriptRoot 'lib\ProxyCommon.ps1')
    $settings = Get-AgpSettings
    if ([string]$settings.sessionCheck -ne 'off') {
        $proxy = Resolve-AgpProxy -Settings $settings -Quick
        $launched = [bool]$env:ANTIGRAVITY_V2RAYN_PROXY
        $model = $null; $user = $null

        if ($launched -and -not $proxy.Listening) {
            $model = "[v2rayn-proxy] Antigravity was started with proxy $env:ANTIGRAVITY_V2RAYN_PROXY but the V2RayN port $($proxy.Host):$($proxy.Port) is not listening. Network-dependent commands and model requests may fail until V2RayN is running."
            $user  = "**V2RayN 代理未运行**：Antigravity 以代理 ``$env:ANTIGRAVITY_V2RAYN_PROXY`` 启动，但 $($proxy.Host):$($proxy.Port) 未监听。请启动 V2RayN。"
        } elseif (-not $launched) {
            $state = 'not listening'
            if ($proxy.Listening) { $state = 'listening' }
            $model = "[v2rayn-proxy] Antigravity was NOT started via the V2RayN proxy launcher, so HTTP(S)_PROXY is not set for this session. V2RayN endpoint $($proxy.Url) is $state. If network requests fail, suggest the 'Antigravity (Proxy)' shortcut or the v2rayn-proxy skill."
            $user  = "未通过 V2RayN 代理启动 Antigravity（代理 ``$($proxy.Url)`` 状态：$state）。如需代理，请使用桌面上的 **Antigravity (Proxy)** 快捷方式启动；可用 ``proxy-config.ps1 -Set sessionCheck=off`` 关闭此提示。"
        }

        if ($model) {
            $out = @{ injectSteps = @(@{ systemMessage = @{ systemMessage = $model; metadata = @{ user_markdown = $user } } }) }
        }
    }
} catch {
    $out = @{}
}
$json = '{}'
try { $json = ConvertTo-AgpAsciiJson $out } catch { $json = '{}' }
if (-not $json) { $json = '{}' }
[Console]::Out.Write($json)
