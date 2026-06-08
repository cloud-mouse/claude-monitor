# Claude Monitor

轻量级 macOS 桌面悬浮胶囊，实时监控 Claude Code 会话运行状态。

## 功能

- 🟢 **状态实时监控** — 通过颜色区分 `busy`（处理中/橙色）和 `idle`（等待输入/绿色）
- 🔔 **状态变更通知** — 会话状态变化时发送 macOS 系统通知
- 📌 **桌面悬浮胶囊** — 始终置顶的毛玻璃胶囊，不干扰正常工作
- ✋ **拖动 + 边缘吸附** — 自由拖动到任意位置，靠近屏幕边缘自动吸附
- 📱 **多会话切换** — 横向滑动浏览多个 Claude Code 会话
- ⚡ **快捷打开** — 点击会话自动打开所在终端 / Cursor / VS Code
- 📊 **菜单栏图标** — 状态栏图标，快速显示/隐藏/退出
- 💾 **位置记忆** — 自动记住胶囊位置

## 依赖

- macOS 13+ (Ventura)
- Xcode Command Line Tools (`xcode-select --install`)

## 构建

```bash
# 构建 .app bundle
make bundle

# 安装到 /Applications
make install

# 或直接运行（开发模式）
make run
```

## 使用

1. 构建并安装后，双击 `ClaudeMonitor.app` 启动
2. 悬浮胶囊出现在屏幕顶部居中位置
3. 当有 Claude Code 会话运行时，胶囊自动显示会话信息：
   - 🟢 绿色圆点 = 等待用户输入 (idle)
   - 🟠 橙色圆点 = 正在处理 (busy)，圆点会有脉冲动画
4. **点击**会话 → 打开所在终端/IDE
5. **右键**会话 → 更多选项（Terminal / Cursor / VS Code / Finder / 拷贝路径）
6. **拖动**胶囊到想要的位置，靠近屏幕边缘自动吸附
7. **菜单栏图标** → 显示/隐藏面板、退出

## 工作原理

应用通过监控 `~/.claude/sessions/` 目录下的 JSON 文件来获取会话信息：

```
~/.claude/sessions/<pid>.json
{
  "pid": 6399,
  "sessionId": "uuid",
  "cwd": "/path/to/project",
  "status": "busy" | "idle",    ← 关键字段
  "updatedAt": timestamp_ms
}
```

- 文件监控 (DispatchSource) + 轮询 (2秒) 双重保障
- 进程树分析自动检测父应用（Terminal / Cursor / VS Code 等）

## 体积

编译后仅 ~320KB，运行内存 ~40MB。

## 技术栈

- Swift + SwiftUI + AppKit (NSPanel)
- 无第三方依赖
- Swift Package Manager 构建
