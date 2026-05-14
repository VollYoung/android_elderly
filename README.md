# AndroidElderly

一个基于 Flutter + Android 原生前台服务的网络守护 App，面向需要持续提醒网络异常的 Android 设备。

## 功能

- 后台前台服务持续监听 WiFi 和移动网络状态。
- WiFi 或移动网络任意一个不可用时，触发系统级提醒。
- 如果网络持续不可用，每小时重复提醒一次。
- 每次手机解锁时再次检查网络状态，若仍有网络不可用则提醒。
- 可设置本机名称，邮件标题和正文会带上设备名称，方便区分是哪台设备异常。
- 可设置接收邮箱和 SMTP 邮件服务器，网络异常时由 Android 原生守护服务发送邮件。
- 可设置接收短信号码，网络异常时由 Android 原生守护服务发送短信。
- 首页显示邮件发送日志，记录成功、失败和配置不完整等情况。
- 支持开机后自动启动守护服务。
- 已替换默认 Flutter 图标，使用 Material 风格网络守护图标。

## 当前提醒规则

当前规则是：**WiFi 和移动网络只要任意一个不可用，就会触发提醒**。

这意味着：

- WiFi 关闭，移动网络仍可用：会提醒，并尝试发送邮件和短信。
- 移动网络关闭，WiFi 仍可用：会提醒，并尝试发送邮件和短信。
- WiFi 和移动网络都关闭：会提醒；短信仍可尝试发送，邮件会因为没有网络而失败并写入日志。

## 邮件发送

邮件发送已经放在 Android 原生 `NetworkGuardService` 守护服务里，不依赖 Flutter 页面是否打开。因此 App 被划走后，只要前台守护服务仍在运行，仍会继续监听网络并尝试发送邮件。

设置页需要填写：

- 本机名称
- 接收提醒的电子邮件地址
- SMTP 服务器
- SMTP 端口
- 邮箱账号
- 邮箱密码或授权码
- 发件人邮箱
- 连接安全方式

当前原生 SMTP 支持：

- SSL/TLS，常用端口 `465`
- 不加密 SMTP，常用端口 `25`

暂未实现 `STARTTLS 587`。如果使用 Gmail、QQ 邮箱、163 邮箱等服务，多数情况下需要使用邮箱服务商生成的 SMTP 授权码，而不是登录密码。

## 短信发送

短信发送也在 Android 原生 `NetworkGuardService` 守护服务里执行。

需要：

- 在设置页填写接收短信号码。
- 授予 App `SEND_SMS` 权限。
- 设备支持短信能力，并且运营商/SIM 卡允许发送短信。

短信可能产生运营商费用。部分系统或厂商 ROM 可能会限制后台短信发送，需要手动允许短信权限或后台权限。

## 权限

App 使用到的主要 Android 权限包括：

- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `ACCESS_WIFI_STATE`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_SPECIAL_USE`
- `POST_NOTIFICATIONS`
- `RECEIVE_BOOT_COMPLETED`
- `SEND_SMS`
- `USE_FULL_SCREEN_INTENT`

## 实现边界

- 普通第三方 Android App 不能稳定、强制阻止用户关闭 WiFi 或移动数据。
- 普通第三方 Android App 也不能在所有 Android 版本上可靠读取“用户是否手动关闭移动数据开关”的私有状态。
- 当前实现基于 Android `ConnectivityManager` 的网络能力变化来判断 WiFi 和移动网络是否可用。
- 如果两个网络都已关闭，设备没有外网连接，邮件无法真正发出；这种情况下会记录失败日志。
- 要实现强制禁止关闭网络，需要企业设备管理能力，例如 Device Owner / MDM 场景。

## 运行

```bash
flutter pub get
flutter run
```

## 打包 APK

Debug APK：

```bash
flutter build apk --debug
```

Release APK：

```bash
flutter build apk --release
```

常见输出路径：

```text
build/app/outputs/flutter-apk/app-debug.apk
build/app/outputs/flutter-apk/app-release.apk
```

## 日志排查

查看 Android 崩溃日志：

```bash
adb shell dumpsys dropbox --print data_app_crash
```

实时查看关键错误日志：

```bash
adb logcat -v time AndroidRuntime:E flutter:E DartVM:E '*:S'
```

邮件发送成功或失败会写入 App 首页的“邮件发送日志”。
