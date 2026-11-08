---
name: v2rayn-proxy
description: Configure, diagnose and use the local V2RayN proxy for Antigravity. Use when the user wants Antigravity (or commands it runs) to go through V2RayN, wants a proxy launcher / auto-start shortcut, changes the proxy port, or when network requests fail with timeouts, connection resets, 403 region errors or "unable to connect" and a proxy may be needed.
---

# V2RayN proxy for Antigravity

This plugin routes Antigravity through the local V2RayN inbound (v2rayN 7.x default:
mixed HTTP+SOCKS port `127.0.0.1:10808`; v2rayN 6.x: SOCKS 10808 / HTTP 10809).

Proxy settings must exist **before** Antigravity starts (Electron and the agent
language server read them at startup). A plugin cannot run before the client
starts, so the plugin ships a **launcher** that the user starts instead of
`Antigravity.exe`:

1. Find `v2rayN.exe` and read `guiConfigs\guiNConfig.json` -> inbound port.
2. Start v2rayN if the port is not listening; wait up to `waitTimeoutSec`.
3. Probe the port (HTTP CONNECT, then SOCKS5 handshake) to pick the scheme.
4. Set `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`,
   `ANTIGRAVITY_V2RAYN_PROXY` and launch
   `Antigravity.exe --proxy-server=<url> --proxy-bypass-list=<local>;localhost;127.0.0.1;::1`.

All scripts live in `scripts/` next to this skill's plugin root (two levels up
from this file: `<plugin>/scripts/`). Run them with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin>\scripts\<script>.ps1" <args>
```

## Scripts

| Script | Purpose |
| --- | --- |
| `proxy-status.ps1 [-Online] [-Json]` | v2rayN path/running, inbound port, resolved proxy URL, port/protocol check, whether *this* session was launched through the proxy. `-Online` does a real HTTPS request via the proxy. |
| `proxy-config.ps1 [-Set k=v ...] [-Reset]` | Show/change settings in `%LOCALAPPDATA%\AntigravityProxy\settings.json`. |
| `Install-Launcher.ps1 [-Startup] [-ReplaceOriginal] [-Uninstall]` | Create the "Antigravity (Proxy)" Desktop + Start Menu shortcuts; `-Startup` = auto-start at login; `-ReplaceOriginal` rewrites the existing Antigravity shortcuts (backed up). |
| `Start-AntigravityWithProxy.ps1 [-Restart] [-Quiet] [-Direct] [-DryRun]` | The launcher itself. `-DryRun` prints the command it would run. |

Settings keys: `v2rayNPath`, `antigravityPath`, `proxyHost`, `proxyPort` (0 = from
v2rayN), `proxyScheme` (auto/http/socks5), `autoStartV2rayN`, `waitTimeoutSec`,
`onProxyFailure` (ask/continue/abort), `verifyBeforeLaunch`, `verifyUrl`,
`noProxy`, `setElectronFlags`, `sessionCheck` (warn/off).

## Procedures

**Check status / diagnose network failures**
1. Run `proxy-status.ps1` (sandboxed is fine for local checks; the port probe
   talks to 127.0.0.1 and may be blocked by the sandbox — if `portListening` is
   False but the user says v2rayN is running, rerun with sandbox bypass).
2. For a real reachability test run `proxy-status.ps1 -Online` (needs network,
   so it needs sandbox bypass).
3. Interpret: v2rayN not found -> set `v2rayNPath`; port not listening -> start
   v2rayN; online check fails while port is OK -> the V2RayN node/subscription is
   broken (tell the user to switch node in V2RayN, not a plugin problem);
   `launchedViaPlugin = False` -> Antigravity was started normally.

**First-time setup**
1. Run `proxy-status.ps1` to confirm detection.
2. Run `Install-Launcher.ps1` (add `-Startup` if the user wants V2RayN +
   Antigravity to start at login, `-ReplaceOriginal` if they want their usual
   shortcut to be proxied).
3. Tell the user to quit Antigravity and start it from **Antigravity (Proxy)**.

**Restart the current Antigravity through the proxy**
Do not run the launcher with `-Restart` yourself: it closes Antigravity, which
kills this agent session mid-command. Ask the user to close Antigravity and use
the shortcut (or run the launcher themselves).

**One-off commands through the proxy** (when the session was not launched via
the plugin): prefix the command's environment, e.g.
`$env:HTTPS_PROXY='http://127.0.0.1:10808'; $env:HTTP_PROXY=$env:HTTPS_PROXY; git clone ...`
For persistent tool config only on explicit request: `git config --global http.proxy http://127.0.0.1:10808`,
`npm config set proxy http://127.0.0.1:10808`, `pip config set global.proxy http://127.0.0.1:10808`.

## Notes
- Do not toggle V2RayN's Windows system proxy for the user; the launcher uses
  per-process settings and does not need it.
- Never write V2RayN's own config files; only read `guiNConfig.json`.
- Launcher log: `%LOCALAPPDATA%\AntigravityProxy\launcher.log` — read it first when the shortcut "does nothing".
