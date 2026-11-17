# ADB WiFi Toggle

安卓桌面小组件：一个开关控制无线调试（ADB over WiFi）的启停，并实时显示 IP、端口、WiFi 名与守护状态。单 APK，无需单独安装脚本；无前台服务、无开机自启，点击才刷新。

## 功能

- **2x2** 小组件，拨动开关一眼可辨。
- 点**开关区**：切换无线调试（开=置 `adb_wifi_enabled=1` 并启动保活守护；关=置 0 并停守护）。
- 点**信息区**：刷新 IP / 端口 / WiFi / 守护状态。
- **保活守护**：开启期间若系统自行关闭无线调试，守护会把它拉回，防止过期或不稳定因素掉线。守护非常驻开机，仅随开关开启而运行。

## 前提

- 已 Root（Magisk，需保留交互式 su；改包名版亦可）。
- 系统「开发者选项 → 无线调试」可用。
- 首次点击开关时 Magisk 会弹授权请求，选允许并记住。

## 安装

1. 从 [Releases](https://github.com/cs445194891/adb-wifi-widget/releases) 下载 `adb-wifi-widget-debug.apk` 并安装。
2. 桌面长按 → 添加小组件 → 全部应用 → 最下方「安卓小部件」→ ADB WiFi Toggle，拖到桌面。

## 从源码编译（可选）

推送代码到仓库会自动触发 GitHub Actions 构建；在对应运行的 Artifacts 里下载 APK，或看 Releases。细节见 `.github/workflows/build.yml`。本机若有 JDK 17 + Android SDK，也可直接打开工程用 Gradle 编译。

## 注意

- **卸载会自动清理**：控制/守护脚本、flag、日志都放在 App 私有目录。无论用 `adb uninstall` 还是在手机上直接卸载，Android 都会删除该目录；守护检测到自身文件消失会立即退出，不留后台进程、不留 `/data/adb` 残留。
- **更新需先卸载**：APK 用 debug 签名，Release 每次构建签名不同，`adb install -r` 会失败，先卸载旧版再装。卸载会清掉上面那些脚本文件（重装后首次刷新自动重建），同时**桌面小组件实例会被清除，需重新拖入**。
- **状态非实时**：无后台服务，从系统设置改了无线调试后，点一下信息区刷新。

## 卸载

两种方式等价，都会清理干净（含脚本与守护）：

```bash
adb uninstall com.adbwifitoggle
```

或在桌面长按图标 → 卸载 / 设置 → 应用 → 卸载。
