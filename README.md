# typelessctl

[![ci](https://github.com/Test2049micro/typelessctl/actions/workflows/ci.yml/badge.svg)](https://github.com/Test2049micro/typelessctl/actions/workflows/ci.yml)

**Typeless for macOS 的命令行控制器 + 静默守卫（非官方工具）**

`typelessctl` 让听写应用 [Typeless](https://www.typeless.com) 以「纯后台听写」方式运行：
不进 Dock、启动时自动弹出的主界面窗口自动关闭、而听写浮动条与快捷键完全不受影响。
同时提供状态查看、设置读写、听写历史导出等日常操作命令。

> ⚠️ **非官方**：与 Typeless（Simply LLC）无任何关联。通过 macOS 无障碍 API 与本地数据文件工作，不修改应用包、不逆向协议、不接触网络账号接口。

## 它解决什么问题

Typeless 手动启动时必定弹出 hub 主界面窗口。本工具的守卫（guard）用「无障碍点关闭按钮」
的方式把它关掉——**不重启 App、不注入、不依赖调试端口**，且是「意图感知」的：

| 场景 | 行为 |
|---|---|
| App 启动后 15 秒内自动弹出的主界面 | 自动关闭（启动闪烁 ≤4s 消失） |
| 你稍后从托盘菜单手动打开的主界面 | **放行不关**（正常使用 App 的 GUI） |
| 听写浮动条（Status）/ 登录窗口 | 永远不动 |

## 安装

要求：macOS 12+、Xcode Command Line Tools（提供 `python3` / `sqlite3`），
运行本命令的终端需授予「辅助功能」权限（系统设置 → 隐私与安全性 → 辅助功能）。

```bash
git clone https://github.com/Test2049micro/typelessctl.git
cd typelessctl
bin/typelessctl doctor          # 体检：确认各项能力可用
bin/typelessctl guard install   # 注册 launchd 守卫（每 2 秒巡查一次）
```

卸载：`bin/typelessctl guard uninstall`

## 命令一览

```
typelessctl status                     运行状态：进程/窗口/守卫/Dock 模式（--json 可选）
typelessctl doctor                     能力与权限体检
typelessctl bootcheck                  开机后自检：登录自启/静默形态/守卫三件套（重启后跑一次）
typelessctl app launch|quit|status     启停 App
typelessctl hub close|status|show      关/看主界面（show 未实现，见能力边界）
typelessctl guard install|uninstall    安装/卸载静默守卫
typelessctl guard enable|disable       恢复/暂停守卫（disable = 回到 App 原生窗口行为）
typelessctl settings list|get|set      读/写 App 设置（白名单键，写后读回核验）
typelessctl history list [N]           最近 N 条听写历史（本地 SQLite 直读）
typelessctl history export [file.csv]  全量导出 CSV（默认 chmod 600，仅本机）
```

环境变量：`TYPELESSCTL_GRACE`（守卫宽限秒数，默认 15）、`TYPELESSCTL_STATE`（状态目录，默认 `~/.typelessctl`）。
退出码契约：`0` 成功 · `2` 用法错 · `3` 权限缺 · `4` 不支持 · `5` 数据读写失败 · `6` 结果未核验。

## 能力边界（诚实声明）

| 能力 | 状态 | 说明 |
|---|---|---|
| 启动/退出 App | ✅ 实测 | `open -a` / AppleScript quit |
| 关闭主界面窗口 | ✅ 实测 | AX 点关闭钮，App 不退出、听写不受影响 |
| 设置读写 | ✅ 实测 | 白名单键直写 `app-settings.json`，写后读回核验；App 运行中内存态可能回写，冲突时报 `6` |
| 历史导出 | ✅ 实测 | 只读 SQLite `history_v2` 表 |
| 唤回主界面 (`hub show`) | ❌ 不支持 | 无公开通道：`typeless://` 协议仅处理 OAuth 回调；请用 App 托盘菜单 |
| 触发听写 | ❌ 不支持 | 听写由 App 全局快捷键（Fn）驱动，无公开触发接口 |
| CDP 调试端口 / 修改应用包 | ⛔ 放弃 | 需重启 App（视觉闪动）；应用包受签名与 App Management 保护 |

## 隐私

- 本仓库**不包含、也不读取**你的账号会话文件（`app-storage.json`）、听写数据库与录音。
- `history export` 的导出文件默认落在 `~/.typelessctl/`，权限 600，仅本机。
- 守卫日志只记录「关闭了哪个窗口名与时间点」，不含听写内容。

## 原理

Typeless 启动逻辑（源码定位）：登录项自启 → 静默模式（只开浮动条）；手动启动 → 弹主界面。
由于应用包受 macOS「App 管理」保护（原位改写 EPERM、换包被 Gatekeeper 移除），
本工具选择**运行时无障碍操作**：每 2 秒检查一次，若主界面在 App 启动宽限期（默认 15s）内出现，
就模拟点击它的红色关闭按钮——与用户手点的效果完全一致，且不抢焦点。

## 已知限制

- **依赖 AX 权限**：运行命令的终端需在「系统设置 → 隐私与安全性 → 辅助功能」中被勾选。
  权限缺失时 `doctor` / `bootcheck` 会显式报 FAIL，不会伪装成通过。
- **`hub show` 未实现**：无公开通道唤回主界面（`typeless://` 仅处理登录回调）；请用 App 托盘菜单，
  或 `typelessctl pause` 临时放行守卫后手动打开。
- **`settings` 写入与 App 内存态竞争**：App 运行中可能用内存值回写覆盖，命令会读回核验并在不符时报退出码 6；
  建议先退出 App 再改设置。
- **宽限期是启发式**：守卫只关「App 启动后 15s 内出现」的主界面，以此区分「自动弹出」与「用户手动打开」。
  若你习惯在启动后极短时间内就主动打开主界面，它可能被误关——可调大 `TYPELESSCTL_GRACE` 或 `typelessctl pause`。
- **依赖**：macOS 自带 `bash`(3.2)、`python3`、`sqlite3`、`osascript`，无第三方运行时。

## License

MIT
