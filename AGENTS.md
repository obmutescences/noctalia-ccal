# AGENTS.md

## 项目定位

本目录是最终交付的 Noctalia v5 插件目录。生成或修改代码时只改本目录，不要把 `dms-plugin-ccal/` 或 `official-plugins/` 的文件复制到这里当作产物。

当前插件只支持中文界面和中文文档。

## 权威参考

- 本地官方文档：`../Plugin Development plugins for Noctalia v5 _ Noctalia Docs.html`
- 官方插件样例：`../official-plugins/example/`
- 真实 service + widget 模式：`../official-plugins/screen_recorder/`
- 原始农历逻辑参考：`../dms-plugin-ccal/services/ChineseCalendarService.qml`

旧的总结、调试、安装脚本和测试脚本已经移除。不要恢复旧文档中的 `noctalia.exec({ cmd, args })`、`runAsync({ cmd, args })` 等写法。

## Noctalia v5 插件规范

插件目录必须直接包含：

```text
plugin.toml
*.luau
```

本地开发放置路径：

```text
$XDG_DATA_HOME/noctalia/plugins/ccal/
```

如果 `XDG_DATA_HOME` 未设置，通常是：

```text
~/.local/share/noctalia/plugins/ccal/
```

插件 id 是 `noctalia/ccal`，本地目录名必须是 id 斜杠后的 `ccal`，否则本地启用和覆盖可能不生效。

`plugin.toml` 中：

- `name` 和 `min_noctalia` 是必需字段。
- `[[service]]` 是无 UI 后台单例。
- `[[widget]]` 是可添加到 bar 的显示入口。
- 根级 `[[setting]]` 是插件级配置，所有 entry 都能通过 `noctalia.getConfig(key)` 读取。
- `[[widget.setting]]` 是 widget 实例配置，优先给 widget 展示用。
- service 需要读取的配置必须放在根级 `[[setting]]`，否则会读不到并在日志里产生未声明配置警告。

## Luau API 注意事项

按官方文档和官方插件代码使用：

```lua
noctalia.commandExists("ccal")
noctalia.runAsync("ccal -x -g -u 6 2026", function(result)
  if result.exitCode == 0 then
    -- result.stdout
  end
end)
noctalia.http({ url = url }, callback)
noctalia.json.decode(body)
noctalia.state.set(key, value)
noctalia.state.get(key)
noctalia.state.watch(key, fn)
```

不要使用这些旧写法：

```lua
noctalia.exec({ cmd = "ccal", args = {} })
noctalia.runAsync({ cmd = "ccal", args = {} }, callback)
```

跨 entry 状态只能放 plain data：字符串、数字、布尔和由这些组成的 table。不要放函数或 userdata。

## 当前架构

`ccal_service.luau`：

- 检查 `ccal` 是否可用。
- 执行 `ccal -x -g -u <month> <year>`。
- 解析 XML：
  - `ccal:month cname` -> 农历月头，例如 `丙午年五月小15日始`。
  - `ccal:day value/cdate/cmonthname/cdatename/leap` -> 每日农历、节气、闰月信息。
- 从 `holiday-cn` 获取当年节假日和调休数据。
- 发布 `ccalAvailable`、`lunarDataCache`、`holidayCache`、`dataVersion`、`holidayDataVersion`。
- 监听 `noctalia.state.watch("command", ...)`，响应 widget 发来的刷新请求。

`calendar.luau`：

- 只渲染 bar widget。
- 通过 `barWidget.getConfig("date_format")` 读取显示格式。
- 通过 `noctalia.getConfig("refresh_interval")` 读取插件级刷新间隔。
- 通过 `noctalia.state.watch` 监听 service 发布的数据。
- 点击时只写入 `noctalia.state.set("command", { action = "refresh" })` 静默请求后台刷新，不打开 Noctalia 官方面板，也不弹通知。

Noctalia v5 官方 Luau `[[widget]]` 没有 dms `popoutContent` 那种自定义 bar 弹窗 API。不要在当前 Luau 插件里伪造 QML 弹窗或混用 `manifest.json`；如果以后要做完整月份网格弹窗，需要单独评估 Noctalia QML 插件机制。

## IPC

service 无输出目标，测试时 target 用 `all`：

```bash
noctalia msg plugin noctalia/ccal:ccal_service all refresh
```

widget 实例可用 focused：

```bash
noctalia msg plugin noctalia/ccal:calendar focused set_format "yyyy/MM/dd LL"
```

## 开发约束

- 只维护中文文案；当前不使用 `translations/`，不要新增英文翻译文件。
- 当前仓库根目录下的交付目录是 `noctalia-ccal/`，但安装到 Noctalia 时目录名是 `ccal/`。不要恢复嵌套的 `noctalia-ccal/noctalia-ccal/` 目录。
- 不要新增安装/测试 shell 脚本，除非用户明确要求。
- 修改 Luau 后运行 `stylua` 格式化。
- 能用官方插件样例验证的 API，优先以 `official-plugins/` 为准。
