# v2rayn-proxy

- The user routes Antigravity through a local V2RayN proxy (default `http://127.0.0.1:10808`). When a command fails with network errors (timeouts, connection reset, TLS handshake failures, region-blocked 403s from Google/GitHub/npm/PyPI), consider the proxy first and use the `v2rayn-proxy` skill to diagnose instead of retrying blindly.
- If `HTTPS_PROXY` is already set in the environment (Antigravity was started by the proxy launcher), commands run outside the sandbox inherit it automatically; do not add extra proxy flags.
- Never modify V2RayN's own configuration files or toggle the Windows system proxy unless the user explicitly asks.
