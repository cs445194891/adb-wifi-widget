# ADB WiFi Toggle

安卓桌面小组件：一个开关控制无线调试（ADB over WiFi）的启停与守护进程，并实时显示 IP、端口、WiFi 名与守护状态。无常驻前台服务，点击才刷新。

## 功能

- **2x2** 小组件，拨动开关一眼可辨。
- 点**开关区**：切换无线调试（开=启动守护并置 `adb_wifi_enabled=1`；关=停守护并置 0）。
- 点**信息区**：刷新 IP / 端口 / WiFi / 守护状态。
- 守护脚本由 Magisk `service.d` 开机自启，MIUI 杀后台不影响。

## 前提

- 已 Root（Magisk，需保留交互式 su 提示；改包名版亦可）。
- 系统「开发者选项 → 无线调试」可用。
- 首次点击开关时 Magisk 会弹授权请求，选允许并记住。

## 安装

1. 从 [Releases](https://github.com/cs445194891/adb-wifi-widget/releases) 下载 `adb-wifi-widget-debug.apk` 并安装。
2. 安装设备侧脚本（需 root）：

```bash
adb push device/ /sdcard/Download/adb-wifi-widget/
adb shell 'su -c "sh /sdcard/Download/adb-wifi-widget/install-device.sh /sdcard/Download/adb-wifi-widget"'
```

3. 桌面长按 → 添加小组件 → 全部应用 → 最下方「安卓小部件」→ ADB WiFi Toggle，拖到桌面。

## 从源码编译（可选）

推送代码到仓库会自动触发 GitHub Actions 构建；在对应运行的 Artifacts 里下载 APK，或看 Releases。细节见 `.github/workflows/build.yml`。本机若有 JDK 17 + Android SDK，也可直接打开工程用 Gradle 编译。

## 注意

- **关闭开关会断连**：关会把 `adb_wifi_enabled` 置 0，若你正用无线 adb 连接，会立刻掉线，需到开发者选项手动重开。这是「用无线 adb 管一个能关无线 adb 的开关」的固有矛盾。
- **更新需先卸载**：APK 用 debug 签名，Release 每次构建签名不同，`adb install -r` 会失败，先卸载旧版再装。卸载不影响设备侧脚本，但**桌面小组件实例会被清除，需重新拖入**。
- **状态非实时**：无后台服务，从系统设置改了无线调试后，点一下信息区刷新。

## 卸载

```bash
adb uninstall com.adbwifitoggle
```

如需恢复原来的「永久常开」守护，见 `device/install-device.sh` 的备份逻辑（旧脚本备份为 `90_adb_wifi_keepalive.sh.bak-<时间戳>`）。
