# ADB WiFi Toggle 桌面小组件

一个 Android 桌面小组件：一个开关启停"无线调试 + 守护进程"，并显示 IP、端口、WiFi 名、已授权主机。

**无常驻服务**：状态只在点击小组件或系统刷新时更新，不会自己定时变色。

---

## 重要前提与边界（先读）

1. **需要 Root（Magisk su）**。首次点击开关时，Magisk 会弹授权请求，必须允许。
   需保留交互式 su 提示的 Magisk 版本（改包名版亦可）；若日后升到移除交互式 su 的版本
   （如 31.1+），此方案需重新评估。

2. **"已授权主机"不等于"此刻的连接"**。`adb_keys` 里存的是曾授权过的电脑公钥注释
   （形如 `user@hostname`），adbd 不向应用暴露当前实时客户端名。所以这一格显示的是
   **已授权的主机**，不是严格意义上的"当前连接设备"。IP/端口/SSID 是实时的。

3. **状态非实时**。点击开关区 = 切换；点击信息区 = 刷新状态。没有后台服务，所以从
   系统设置里手动关掉无线调试后，小组件不会自动变色，需要点一下信息区。

4. **MIUI 的保活**：设备侧守护脚本由 Magisk 的 `service.d` 开机启动，不依赖 App 存活，
   MIUI 杀后台不影响它。但 App 首次申请 root 授权后要确认"记住选择"。

---

## 目录结构

```
adb-wifi-widget/
├── .github/workflows/build.yml   # GitHub Actions 在线编译配置（推荐）
├── build.sh                      # 本机一键搭建编译环境并构建 APK（备选）
├── app/                          # Android 工程源码
├── device/
│   ├── adb_wifi_ctl.sh           # 统一控制入口（on/off/toggle/status）
│   ├── adb_wifi_daemon_v2.sh     # 读 flag 的守护脚本
│   └── install-device.sh         # 设备侧安装器
└── output/                       # 构建产物（本机 build.sh 后生成）
```

---

## 一、构建 APK

有两种方式。**推荐方式 A**（无需本地环境）；本机已有 JDK/SDK 才用方式 B。

### 方式 A：GitHub Actions 在线编译（推荐，零本地环境）

云端帮你装 JDK 17 + Android SDK + Gradle 8.2 并编译，你只需推代码、点按钮、下载 APK。
公开仓库**完全免费、不限时长**；私有仓库免费档约 $12/月（≈2000 Linux 分钟），足够个人用。

**前提**：一个 GitHub 账号。国内网络需给 git 和浏览器配代理（按你自己的代理端口配置）。

#### 第 1 步：把项目推到 GitHub

在 GitHub 网页新建一个空仓库（建议设为 **Public**，免费不限时长；名字随意，如 `adb-wifi-widget`），
**不要**勾选 README/license（保持空仓库）。然后在本地终端：

```bash
cd adb-wifi-widget

# 若你的 git 走代理（国内需要），先设置（仅当前仓库生效）
# 把 <端口> 换成你自己的本地代理端口
git config http.proxy socks5://127.0.0.1:<端口>
git config https.proxy socks5://127.0.0.1:<端口>

git init
git add .
git commit -m "init: adb wifi toggle widget"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

> `<你的用户名>/<仓库名>` 换成你自己的。push 时会弹 GitHub 登录：
> 用 **Personal Access Token** 当密码（GitHub 已不支持账号密码直接 push）。
> 生成路径：GitHub → Settings → Developer settings → Personal access tokens → Tokens(classic)，
> 勾选 `repo` 权限。

#### 第 2 步：触发构建

push 会自动触发一次；之后可随时手动触发：

- 打开仓库网页 → **Actions** 标签 → 左侧选 **Build ADB WiFi Widget**
- 点 **Run workflow** → 再点绿色 **Run workflow**

首次构建约 2–4 分钟（要下 SDK 组件）。点进本次运行可看实时日志。

> ⚠️ 若构建**失败**：点进去看红色报错，把报错原文发我，我改 workflow 或工程配置后你
> 再 `git add . && git commit && git push` 即可重跑。首次失败多为环境参数微调，属正常。

#### 第 3 步：下载 APK

构建成功后，在本次运行页面底部 **Artifacts** 区点 **`adb-wifi-widget-debug`** 下载 ZIP，
解压得到 `app-debug.apk`（已用 debug 签名，可直接安装）。产物默认保留 90 天。

> 下载工件在网页端进行，浏览器要走代理；若公司/家庭网络直连 GitHub 慢，挂上你的代理。

**为何用 `assembleDebug` 而非 release**：本工程 release 构建类型未配置签名密钥，
`assembleRelease` 只会产出**未签名** APK（装不上）。debug 版用系统默认 debug 签名，
自用完全够。日后若要正式签名版，可加 keystore + GitHub Secrets 改造。

### 方式 B：本机编译（macOS，备选）

```bash
cd adb-wifi-widget
chmod +x build.sh
./build.sh
```

脚本会自动下载 JDK 17 + Android SDK cmdline-tools + Gradle，编译出
`output/adb-wifi-widget-debug.apk`。若需代理，运行时传环境变量：
`PROXY="socks5://127.0.0.1:<端口>" ./build.sh`（不设则直连）。

> 若你已有 Android Studio / JDK / SDK，可直接用 Android Studio 打开工程根目录编译。

## 二、安装设备侧脚本（手机）

```bash
# 推送脚本到手机
adb push adb-wifi-widget/device/ /sdcard/Download/adb-wifi-widget/

# 以 root 安装（会备份并替换旧的常开守护脚本）
adb shell 'su -c "sh /sdcard/Download/adb-wifi-widget/install-device.sh /sdcard/Download/adb-wifi-widget"'
```

安装器会打印当前状态，确认四项信息都能取到。

## 三、安装小组件 APK

APK 来源二选一：方式 A 下载解压得到的 `app-debug.apk`，或方式 B 的
`output/adb-wifi-widget-debug.apk`。

```bash
adb install -r /path/to/app-debug.apk
```

然后在桌面长按 → 小组件 → 找到 "ADB WiFi Toggle" → 拖到桌面。

## 四、使用

| 操作 | 效果 |
|---|---|
| 点开关区（LED + 文字） | 切换无线调试：开=启守护并 pin `adb_wifi_enabled=1`；关=停守护并置 0 |
| 点信息区（IP/端口等） | 重新读取并刷新显示 |

命令行等价操作（root）：

```bash
adb shell 'su -c "/data/adb/adb_wifi_ctl.sh status"'
adb shell 'su -c "/data/adb/adb_wifi_ctl.sh off"'
adb shell 'su -c "/data/adb/adb_wifi_ctl.sh on"'
```

---

## 回退（恢复原来的"永久常开"）

安装器已把旧开机脚本备份为 `90_adb_wifi_keepalive.sh.bak-<时间戳>`。回退步骤：

```bash
adb shell 'su -c "
  cd /data/adb/service.d
  BAK=\$(ls -1 90_adb_wifi_keepalive.sh.bak-* | tail -1)
  cp \"\$BAK\" 90_adb_wifi_keepalive.sh
  chmod 755 90_adb_wifi_keepalive.sh
  rm -f /data/adb/adb_wifi_daemon_v2.sh /data/adb/.adb_wifi_enabled
  /data/adb/adb_wifi_ctl.sh on
"'
adb reboot
```

卸载小组件：`adb uninstall com.adbwifitoggle`（不影响设备侧脚本）。

---

## 失效条件（什么情况下这套东西不成立）

1. **升到 Magisk 31.1**：交互式 su 被移除，App 申请 root 的机制要重做。
2. **MIUI 修订 service.d 行为**：开机脚本不执行则守护不自启（概率低，Magisk 层实现）。
3. **改了 WiFi 网络**：动态端口会变，但小组件刷新时会重新取，不影响。
4. **v2 守护 flag 文件丢失**：默认回退为 1（常开），不会导致调试关闭，但开关可能失灵；
   重装一次 `install-device.sh` 即可。

## 实测验证结论（2026-11-18，小米 thyme / Android 12 / MIUI）

- **在线编译已验证**：GitHub Actions 构建成功，产物 APK 经 gh-pages 分支取回并装机成功
  （本机无 JDK/SDK，全程走在线编译）。
- **小组件渲染已验证**：`widget.xml` 早期用 `<View>` 做占位/分隔线，RemoteViews 白名单禁止
  inflate `android.view.View`，launcher 渲染时报 `Class not allowed to be inflated`，回退成
  "载入窗口小部件时出现问题"。已改为 `FrameLayout`（白名单内），桌面正常显示。
- **su 调用已验证**：`su` 位于 `/product/bin/su`；以 App uid 实测按名字 `su -c` 即可静默成功
  （Magisk 改包版保留交互式 su），无需改绝对路径。App uid 变化后需重新授权一次即可。
- **SSID 解析已验证**：从 `cmd wifi status` 的 `WifiInfo: SSID:"..."` 行精确提取引号内名称，
  实测取到实时 SSID（具体值不记录；此前贪婪 sed 会把 BSSID 一并带出，已修）。

## 仍需注意（诚实标注）

- **每次更新 APK 需先卸载**：GitHub Actions 用 runner 临时 debug keystore 签名，每次构建签名
  都不同，`adb install -r` 会因签名不匹配失败，必须先 `adb uninstall`。要免卸载更新需固化
  debug keystore（仓库存 keystore + workflow 配 signingConfig），**尚未做**。
- **MIUI USB 安装拦截**：adb 直装会被"通过 USB 安装应用"开关拦截，本次用 root 静默安装绕过。
- **关闭开关会切断无线 adb**：点"关闭"会置 `adb_wifi_enabled=0`；若你正用无线 adb 管理，
  会立刻失去连接，需手动到开发者选项重开。这是该方案的固有矛盾（用无线 adb 管一个能关
  无线 adb 的开关），已确认维持现状。
- **刷新要用 App 自定义 action**：命令行主动刷新应发
  `su -c "am broadcast -a com.adbwifitoggle.REFRESH -n com.adbwifitoggle/.AdbWifiWidget"`。
  直接发系统 `android.appwidget.action.APPWIDGET_UPDATE` 且不带 `appWidgetIds` extra 时，
  `onUpdate` 收到空数组、渲染循环不执行，易被误判为"刷新无效"。
- **GitHub Actions action 版本、各 launcher 的 widget 缩放表现**随时间/机型变化，届时按实际更新。

## GitHub Actions 配置的失效条件

- 仓库设为私有且超出免费额度（$12/月，约 2000 Linux 分钟）——个人自用几乎不可能触发。
- GitHub 改动 Actions 计费或 action 接口（低概率，届时改 `build.yml`）。
- 国内网络无法访问 GitHub（需代理；若代理失效则 push 和下载工件都会失败）。
