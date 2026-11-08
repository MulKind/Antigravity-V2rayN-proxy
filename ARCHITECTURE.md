# Technical Architecture: Antigravity V2RayN Proxy

本文档详细剖析 `v2rayn-proxy` 的技术原理、网络分层设计与 Antigravity 自定义系统的深度集成机制。

---

## 1. 架构背景与核心痛点（The Bootstrapping Problem）

Antigravity 作为一款基于现代 Web 与语言模型驱动的代码智能体客户端，其底层依赖于 **Electron (Chromium) 渲染与网络引擎**，以及背后的 **Language Server (gRPC/Connect) 进程树**。

在网络受限环境下，如果要在启动 Antigravity 时走 V2RayN 本地代理，存在天然的“先有鸡还是先有蛋”的悖论：
- **插件加载时机过晚**：Antigravity 的插件系统（`plugins/`、`skills/`、`hooks.json`）只有在客户端主进程成功启动、读取配置并初始化语言服务器之后才会激活。
- **启动期网络阻断**：若启动前代理未连接，Antigravity 首次联网检查、账户验证及模型通信便会遭遇 TLS 握手超时或 403 地区限制，甚至导致主界面卡死或空白。
- **Chromium 网络栈不可热载**：Chromium 的网络服务（Network Service）在主进程初始化阶段即确定代理后端。启动后在 UI 内部修改环境变量，无法热生效于已建立的 Chromium Socket 线程池。

**解决方案**：本插件采用 **“外部智能启动器 + 内部插件生命周期联动”** 的协同架构：
1. **外部预检与注入**：由 `Start-AntigravityWithProxy.ps1` 在进入应用前完成 V2RayN 依赖拉起、端口探测、协议自适应与环境注入。
2. **内部感知与诊断**：通过 Antigravity 插件的 `SessionStart` Hook、`rules/AGENTS.md` 和 `skills/` 为 Agent 赋予运行期健康监测与动态排错能力。

---

## 2. 网络层分层代理设计

```text
┌─────────────────────────────────────────────────────────────┐
│ 用户点击 "Antigravity (Proxy)" (WScript.Shell Minimized)     │
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 启动器进程 (Start-AntigravityWithProxy.ps1)                  │
│  ├─ 自动定位 V2RayN 并检查 127.0.0.1:10808 是否处于 LISTEN   │
│  ├─ 若端口离线：拉起 v2rayN.exe 并轮询等待 (最多 30s)        │
│  ├─ 执行原始 Socket HTTP CONNECT & SOCKS5 握手探测协议       │
│  ├─ 设置当前进程环境：HTTP_PROXY, HTTPS_PROXY, ALL_PROXY,   │
│  │  NO_PROXY=localhost,127.0.0.1,::1,.local                  │
│  └─ 构建启动参数：                                           │
│     --proxy-server=http://127.0.0.1:10808                   │
│     --proxy-bypass-list=<local>;localhost;127.0.0.1;::1     │
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Antigravity.exe (Electron 主进程)                            │
│  ├─ Chromium Network Service 采用 --proxy-server 直连代理   │
│  │  (用于 UI 资源加载、模型 WebSocket、账户同步)            │
│  ▼                                                          │
│ Language Server 守护进程 (继承宿主环境变量)                 │
│  ├─ gRPC / Connect 本地 RPC 经由 NO_PROXY 直连本地端口      │
│  ├─ 终端任务 / 子进程 (git, npm, pip) 继承 HTTP_PROXY       │
│  ▼                                                          │
│ Plugin Runtime                                              │
│  ├─ hooks.json (SessionStart Hook 验证当前代理状态)         │
│  ├─ rules/AGENTS.md (指导模型遇网络异常时自省代理)          │
│  └─ skills/v2rayn-proxy (为用户提供命令式代理运维能力)      │
└─────────────────────────────────────────────────────────────┘
```

### 2.1 环境变量继承体系
启动器设置的环境变量会被 Windows 进程继承机制完整传递给 Antigravity 主进程，并逐级传递给以下层级：
1. **Antigravity 语言服务器** (`exa.language_server_pb`)；
2. **终端与沙箱命令**：Agent 执行 `run_command` 派生的 PowerShell/cmd 子进程将自动感知 `HTTP_PROXY` 与 `HTTPS_PROXY`，直接支持 `git clone`、`npm install`、`pip install` 等无需额外配置代理；
3. **关键回环隔离 (`NO_PROXY`)**：
   必须严格保持 `NO_PROXY=localhost,127.0.0.1,::1,.local`。Antigravity 的前端 UI 与后端语言服务器通过本地端口通信（如 `127.0.0.1:51891`），如果回环流量被错误路由到代理，将直接导致客户端断连。

### 2.2 协议自适应嗅探机制 (`ProxyCommon.ps1`)
V2RayN 各版本入站规则存在差异：
- **v2rayN 7.x**：默认采用统一混合入站（Mixed Inbound），单一端口（如 `10808`）同时支持 HTTP CONNECT 与 SOCKS5 协议；
- **v2rayN 6.x**：通常分离为两个端口（SOCKS `10808`、HTTP `10809`）。

启动器通过低级 .NET Socket 实现零依赖协议探测：
```powershell
# 1. 尝试发送 HTTP CONNECT 请求
$req = "CONNECT www.google.com:443 HTTP/1.1`r`nHost: www.google.com:443`r`n`r`n"
# 若返回 HTTP/1.1 200，则确认为 HTTP 代理

# 2. 若失败，发送 SOCKS5 握手问候 (0x05, 0x01, 0x00)
# 若返回 (0x05, 0x00)，则确认为 SOCKS5 代理
```
依据探测结果自适应组装最优连接串（优先选择 Chromium 兼容度更高的 `http://` 形式）。

---

## 3. 与 Antigravity 插件规范的对齐

本插件完全遵循 Antigravity 官方自定义系统标准：

1. **清单清单 (`plugin.json`)**：
   - 使用规范的 `name`、`displayName`、`description` 与 `suggestedPrompts`。
   - 包含高对比度标准矢量 Logo（`assets/logo.svg`）。
2. **生命周期拦截器 (`hooks.json`)**：
   - 挂载 `SessionStart` 事件，在新会话开启时执行 `session-check.ps1`。
   - 遵循 ProtoJSON 合约：从 stdin 消耗事件元数据，向 stdout 输出格式化响应（包含 `systemMessage` 与 `user_markdown`）。
3. **行为准则 (`rules/AGENTS.md`)**：
   - 强制全局加载的纯 Markdown 规则，规范 Agent 在网络受阻时不要盲目重试，优先建议用户检查 V2RayN。
4. **渐进式技能 (`skills/v2rayn-proxy/SKILL.md`)**：
   - 采用标准 YAML frontmatter，在模型需要排查网络时按需加载详细排错流程与指令手册，节省推理 Context 预算。

---

## 4. 故障隔离与设计健壮性

- **非侵入式配置**：不写入 Windows 注册表的 `Internet Settings\ProxyEnable`，不对全局其它软件产生副作用。
- **并发与死锁保护**：V2RayN 配置文件（`guiNConfig.json`）仅作只读访问（UTF-8 Safe），永不进行反向写操作。
- **平滑重启处理**：在 Antigravity 已经运行的情况下再次点击快捷方式，通过 Windows API 尝试平滑通知窗口关闭，并设置 8 秒优雅降级超时，超时后强制清理孤儿进程后再重新拉起。
- **配置持久化**：用户自定义参数（如修改端口、开启严格验证）存放于独立于插件安装目录的 `%LOCALAPPDATA%\AntigravityProxy\settings.json`，确保插件更新或重新安装时配置不丢失。
