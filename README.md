# Claude Monitor

轻量级 macOS 桌面悬浮胶囊，实时监控 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 会话状态。

## 功能一览

| 功能 | 说明 |
|------|------|
| 🎯 **四态精准监控** | 繁忙 / 待确认 / 空闲 / 离线，通过 Claude Code Hooks 获取精确状态 |
| 📌 **桌面悬浮胶囊** | 始终置顶的毛玻璃胶囊，不遮挡正常工作 |
| ✋ **拖动 + 边缘吸附** | 自由拖动到任意位置，靠近屏幕边缘自动吸附 |
| 📱 **多会话支持** | 横向排列显示所有活跃的 Claude Code 会话 |
| ⚡ **一键跳转** | 点击会话自动激活所在的 Terminal / iTerm / Warp / Cursor / VS Code / IDEA 窗口 |
| 🔔 **系统通知** | 状态变化时发送 macOS 通知（完成时带声音提醒） |
| 📊 **菜单栏图标** | 状态栏图标，快速显示/隐藏面板、退出 |
| 💾 **位置记忆** | 自动记住胶囊位置，重启后恢复 |

## 状态说明

| 状态 | 颜色 | 含义 | 动画 |
|------|------|------|------|
| 🟠 **繁忙** | 温暖橙 | Claude 正在执行任务 | — |
| 🔴 **待确认** | 警示红 | Claude 等待用户授权 / 刚完成输出需要查看 | 脉冲闪烁 |
| 🟢 **空闲** | 清新绿 | 任务完成，等待下一条指令 | — |
| ⚪ **离线** | 灰色 | 会话已结束或出错 | — |

> **精准状态**需要安装 Claude Code Hooks（见下方），未安装时通过会话状态 + 时间智能推断。

## 依赖

- macOS 13+ (Ventura)
- Xcode Command Line Tools (`xcode-select --install`)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

## 安装

```bash
# 克隆仓库
git clone https://github.com/user/claude-monitor.git
cd claude-monitor

# 构建并安装到 /Applications
make install

# 或仅构建 .app bundle
make bundle
```

安装后双击 `ClaudeMonitor.app` 即可启动。

### 其他命令

```bash
make run       # 直接运行（开发模式）
make clean     # 清理构建产物
make uninstall # 卸载
```

## 可选：安装 Hooks（推荐）

安装 Claude Code Hooks 后，悬浮胶囊能获取**精确状态**（正在调用工具 / 等待授权 / 已完成），而非仅依靠 session JSON 的粗略判断。

```bash
./scripts/install-hooks.sh
```

安装完成后需要**重启 Claude Code 会话**才能生效。

Hooks 会在 `~/.claude/settings.json` 中注入以下事件监听：

| Hook 事件 | 触发时机 | 状态 |
|-----------|---------|------|
| `PreToolUse` | Claude 调用工具前 | 🟠 `tool_call` |
| `Notification` (permission_prompt) | Claude 等待用户授权时 | 🔴 `waiting_permission` |
| `Stop` | Claude 完成响应时 | 🟢 `stopped` |
| `StopFailure` | Claude 出错时 | ⚪ `error` |

## 使用方法

1. 启动 ClaudeMonitor，悬浮胶囊出现在屏幕顶部居中位置
2. 当有 Claude Code 会话运行时，胶囊自动显示会话信息
3. **左键点击**会话 → 跳转到所在终端 / IDE 窗口
4. **右键点击**会话 → 更多选项：
   - 切换到所在窗口
   - 在 Terminal / Cursor / VS Code 中打开
   - 在 Finder 中显示
   - 拷贝项目路径
5. **拖动**胶囊到想要的位置，靠近屏幕边缘自动吸附
6. **菜单栏图标** → 显示/隐藏面板、退出

## 支持的终端和 IDE

| 应用 | 点击跳转 | 右键打开 |
|------|---------|---------|
| Terminal.app | ✅ 定位到对应标签页 | ✅ |
| iTerm2 | ✅ 定位到对应 session | ✅ |
| Warp | ✅ 激活窗口 | ✅ |
| Cursor | ✅ 激活窗口 | ✅ |
| VS Code | ✅ 激活窗口 | ✅ |
| IntelliJ IDEA | ✅ 激活窗口 | ✅ |

## 工作原理

### 基础机制

监控 `~/.claude/sessions/` 目录下的 JSON 文件：

```
~/.claude/sessions/<pid>.json
{
  "pid": 6399,
  "sessionId": "uuid",
  "cwd": "/path/to/project",
  "status": "busy" | "idle",
  "updatedAt": timestamp_ms
}
```

- **文件监控** (DispatchSource) + **轮询** (2 秒) 双重保障
- **进程树分析** 自动检测父应用（遍历 ppid 链，最多 15 层）

### Hooks 增强机制

安装 Hooks 后，Claude Code 在关键事件节点调用 `hooks-handler.sh`，将精确状态写入 `/tmp/claude-monitor/state-<session>.json`，悬浮胶囊优先读取此状态文件（120 秒过期），实现毫秒级状态感知。

## 体积与性能

- 编译后约 **320 KB**
- 运行内存约 **40 MB**
- 无第三方依赖

## 技术栈

- Swift + SwiftUI + AppKit (NSPanel)
- NSVisualEffectView 毛玻璃效果
- DispatchSource 文件监控
- AppleScript 终端/IDE 控制
- Swift Package Manager 构建

## 项目结构

```
claude-monitor/
├── Sources/ClaudeMonitor/
│   ├── App.swift              # 入口、AppDelegate、菜单栏
│   ├── FloatingPanel.swift    # 悬浮面板（拖动/吸附/位置记忆）
│   ├── CapsuleView.swift      # 胶囊 UI（状态灯/脉冲动画）
│   └── SessionMonitor.swift   # 会话监控（文件监听/通知/窗口跳转）
├── Resources/
│   ├── hooks-handler.sh       # Claude Code Hooks 状态写入脚本
│   └── AppIcon.icns           # 应用图标
├── scripts/
│   └── install-hooks.sh       # Hooks 一键安装脚本
├── Package.swift
├── Makefile
└── Info.plist
```

## License

MIT
