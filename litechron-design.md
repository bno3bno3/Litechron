# Litechron 设计与脱离方案

> 状态：方案阶段，尚未执行。整理日期 2026-09-20。
> 本文档是改名期间的唯一方案来源，各步骤完成后在文末"待办清单"勾选；全部完成后可归档。

## 1. 目标与原则

**目标**

- 从 Celechron 脱离，新名 **Litechron**，含义是"比 Celechron 更轻量的时间管理软件"。
- 不再使用原项目的名字、logo、图标、官网（celechron.top）和版本号序列。
- 不做新官网。更新方式见第 5 节，先给出零基础设施的默认方案。
- 与官方 Celechron 可在同一台设备上并存安装，互不干扰。

**设计原则**

- 简约、简洁、美观大气。新界面元素必须与现有 Cupertino 风格一致。
- "轻"是品牌核心：图标、文案、依赖都以少为美。

**不变的东西**

- 许可证仍是 GPLv3，LICENSE 文件保留。
- 功能不因改名而变化，改名期间不夹带功能改动。
- 对上游 Celechron 及其作者的署名保留在"关于"页（见 2.5）。

## 2. 现状盘点

### 2.1 决定"能否并存"的标识（必须全部改）

| 类别 | 现值 | 所在位置 |
|---|---|---|
| Android applicationId / namespace | `xyz.nosig.celechron` | `android/app/build.gradle`；main/debug/profile/release 四个 `AndroidManifest.xml` 的 `package`；Kotlin 目录 `android/app/src/main/kotlin/xyz/nosig/celechron/` |
| iOS Bundle ID | `top.celechron.celechron`、`.debug`、`.WidgetExtensions`、`.debug.WidgetExtensions` | `ios/Runner.xcodeproj/project.pbxproj` |
| App Group | `group.top.celechron.celechron` 与 `.debug` 变体 | iOS Runner 3 个 entitlements、WidgetExtensions 3 个 entitlements、macOS 2 个 entitlements；`AppDelegate.swift`、`FlowWidget.swift`、`ECardWidget.swift`；`lib/utils/utils.dart` |
| Keychain 服务名 | `Celechron` | `lib/utils/utils.dart`、`lib/database/database_helper.dart`、`ECardWidget.swift` 的 `kSecAttrService` |
| URL scheme | `celechron://ecardpaypage` | main `AndroidManifest.xml`、`Info.plist`、`ECardWidget.kt`、`ECardWidget.swift`、`lib/main.dart` |
| 后台任务 ID | `top.celechron.celechron.backgroundScholarFetch` | `Info.plist` 的 BGTaskSchedulerPermittedIdentifiers、`AppDelegate.swift`、`option_controller.dart`、`background_app_refresh.dart` |
| MethodChannel | `top.celechron.celechron/ecardWidget` | `MainActivity.kt`、`AppDelegate.swift`、`ecard_widget_messenger.dart` |
| 通知渠道 ID | `top.celechron.celechron.gradeChange`、`.ddlReminder` | `background_app_refresh.dart` |
| Pigeon 通道 | `dev.flutter.pigeon.celechron.FlowMessenger.transfer` | 由 pubspec 包名自动派生，`flow_messenger.dart` 与 `FlowMessenger.swift` 均为生成物 |
| 系统日历名 | `Celechron课表` | `lib/model/calendar_to_system.dart` |
| macOS Bundle ID / 产品名 | `xyz.nosig.celechron` / `celechron` | `macos/Runner/Configs/AppInfo.xcconfig`、`project.pbxproj`、`Runner.xcscheme` |
| Linux / Windows | `xyz.nosig.celechron`、二进制名 `celechron` | `linux/CMakeLists.txt`、`linux/my_application.cc`、`windows/CMakeLists.txt`、`windows/runner/Runner.rc`、`windows/runner/main.cpp` |

说明：

- 系统日历名不只是文案。两个 App 都按名字查找日历，若同名，Litechron 会写入甚至删除官方版的日历。
- Hive box 名、secure storage 键名是 App 内部的，且新 ID 意味着全新安装，无需改动也无需迁移。
- Xcode 工程里带着原作者的 `DEVELOPMENT_TEAM = LAWWU6DFXL`，上 iOS 需换成自己的 Team 并注册 App Group。

### 2.2 品牌与文案（用户可见，改成 Litechron）

| 位置 | 内容 |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | `android:label="Celechron"` |
| `ios/Runner/Info.plist` | CFBundleDisplayName、CFBundleName、CFBundleURLName、三条权限说明文案 |
| `lib/main.dart` | `title`、`HomePage(title:)`、类名 `CelechronApp` |
| `lib/page/option/option_view.dart` | "关于 Celechron"、后台刷新提示文案、"前往项目网站" |
| `lib/page/option/credits_page.dart` | 名称、logo、设计者署名、GPL 说明、ICP 备案号 |
| `lib/page/option/option_controller.dart` | `celechronVersion` getter |
| `lib/worker/background_app_refresh.dart` | 两条通知文案 |
| `lib/model/calendar_to_ical.dart` | `PRODID`、三处导出文件名前缀 `celechron_`、三处分享文案 |
| `lib/model/calendar_to_system.dart` | 日历名、日历描述、`getOrCreateCelechronCalendar` 等方法名 |
| `lib/design/persistent_headers.dart` | 类名 `CelechronSliverTextHeader`、`CelechronHeader`，约 15 处引用 |
| `lib/model/period.dart`、`lib/pigeon/prompt/flow_message_prompt.dart`、`lib/page/flow/flow_controller.dart` | 注释 |
| `README.md`、`banner.png` | 名称与横幅 |
| `assets/logo.png` | 关于页 logo，也是 flutter_launcher_icons 的源图 |
| `android/app/src/main/res/mipmap-*/ic_launcher.png`、`ios/Runner/Assets.xcassets/AppIcon.appiconset/` | 启动图标，由源图生成 |
| `CLAUDE.md`、`AGENTS.md` | 各 4 处提到 Celechron |

启动画面没有品牌元素：Android 是纯色背景，iOS 的 LaunchImage 是空白占位图，不必处理。

### 2.3 连着原项目服务器的线

| 依赖 | 现状 | 影响 |
|---|---|---|
| 版本检查 `https://api.celechron.top/checkUpdate` | `lib/worker/fuse.dart`。接口现返回 `1.3.1+1`，比本地 `1.2.0+1` 新 | fork 每天弹一次"更新可用"，"访问网站"跳到 celechron.top。必须最先切断 |
| 校历配置 `http://calendar.celechron.top/<学期>.json` | `lib/http/time_config_service.dart`，`UgrsSpider`、`GrsSpider` 每学年请求 `-1`、`-2` 两份 | 提供上课节次时间、放假、调休、学期起止。没有它课表无法把节次映射到时间。失败时回退 Hive 缓存，新装机无缓存 |
| 贡献者列表 `https://api.github.com/repos/Celechron/Celechron/contributors` | `lib/http/github_service.dart`，关于页展示 | 改静态名单即可 |
| workmanager 依赖 `https://github.com/Celechron/flutter_workmanager.git` | `pubspec.yaml` | 对方删库则 `flutter pub get` 失败 |

### 2.4 版本

- `pubspec.yaml` 的 `version: 1.2.0+1`。
- `lib/worker/fuse.dart` 硬编码 `version = [1, 2, 0]`、`build = 1`，与 pubspec 分离，两处必须同步。
- 仓库继承了上游标签 `1.0.2`、`1.0.4`、`1.1.0`、`1.2.0`、`1.3.0`。

### 2.5 许可与署名

- 上游为 GPLv3。改名、换 logo、换 ID 均允许，但许可证必须仍是 GPLv3，且 GPL 要求修改版注明修改。
- "关于"页保留：基于 Celechron 二次开发的说明、原作者名单（设计 nosig、空之探险队的 Kate，开发者静态名单）、GPLv3 声明。
- 必须删除：原作者的 ICP 备案号（`浙ICP备2024061973号-2A`）。没有网站、没有备案，挂着它是误导。
- 原 logo 为原作者设计，随改名整体替换。

### 2.6 分发与签名

- `android/app/build.gradle` 的 release 仍使用 debug 签名。正式分发前需生成自己的 keystore，`android/key.properties` 与 `*.jks` 已在 `android/.gitignore`。
- `.github/workflows/code_check.yml` 只做 format 与 analyze，不涉及名称。

## 3. 需要拍板的决定

以下为默认建议，未确认前按默认执行；标记"待确认"的项在执行第 1 步前确认。

| 决定 | 默认 | 备选 | 状态 |
|---|---|---|---|
| 应用 ID | `io.github.bno3bno3.litechron`，没有自有域名的项目通行的反向域名写法 | `com.github.bno3bno3.litechron` |使用io.github.bno3bno3.litechron |
| 版本起点 | `1.0.0+1`；新标签用 `v1.0.0` 形式避免与继承的旧标签撞名 | 沿用 `1.x` 但换 build 序列 | 首次发布用v1.0.0 |
| 更新渠道 | GitHub Releases 发 APK，仓库内 `remote/version.json` 经 jsDelivr 读取 | 暂不做更新检查，只删旧接口 | 采用默认（2026-09-20） |
| 校历配置 | 原接口 + assets 内置兜底（原接口 → Hive 缓存 → assets），不建自己的远程覆盖 | 完整三级读取 | 采用"原接口 + 内置兜底"（2026-09-20） |
| workmanager | 用户在 GitHub 网页 Fork 到 `bno3bno3/flutter_workmanager`，pubspec 指向并固定 commit | 只固定原仓库 commit | 等用户 Fork 后改指向 |
| 关于页署名 | 顶部 Litechron + 版本；"开发"只写 bno3bno3；下方单独一节"本项目基于 Celechron 二次开发，遵循 GPLv3" | 混合名单 | 已确认（2026-09-20） |
| Dart 包名 | 最后一步改为 `litechron`，影响 77 个文件的 import 行 | 内部保留 `celechron` | 最后一步改为 `litechron` |
| Logo | 几何图形 SVG，见第 6 节，先出 2 到 3 版候选 | 委托他人设计 | 表盘改为 3:00（长分针朝上、短时针朝右，构成正向 L）；A/B/C 三版都渲染后挑选 |
| 真机验证 | 装有官方 Celechron 的 Android 设备上确认并存 | 只做 analyze 与 debug 构建 | 暂无设备，先跳过 |
| 仓库名 | GitHub 仓库改名 `Litechron`，GitHub 会自动重定向旧地址 | 保持 | 已经改了 |
| 工作分支 | 从 `main`（29dbb78 起）开 `rebrand/litechron` 分支，工作区已干净 | 直接在 `main` 上改 | 采用默认 |

## 4. 新旧标识对照表

按第 3 节默认值给出，应用 ID 若改，整列同步替换。

| 项目 | 旧 | 新 |
|---|---|---|
| Android applicationId / namespace | `xyz.nosig.celechron` | `io.github.bno3bno3.litechron` |
| Kotlin 目录 | `kotlin/xyz/nosig/celechron/` | `kotlin/io/github/bno3bno3/litechron/` |
| iOS Bundle ID | `top.celechron.celechron` | `io.github.bno3bno3.litechron` |
| iOS Debug Bundle ID | `top.celechron.celechron.debug` | `io.github.bno3bno3.litechron.debug` |
| iOS 小组件 Bundle ID | `top.celechron.celechron.WidgetExtensions` 及 debug 变体 | `io.github.bno3bno3.litechron.WidgetExtensions` 及 debug 变体 |
| App Group | `group.top.celechron.celechron` 及 `.debug` | `group.io.github.bno3bno3.litechron` 及 `.debug` |
| macOS / Linux 应用 ID | `xyz.nosig.celechron` | `io.github.bno3bno3.litechron` |
| Keychain 服务名 / accountName | `Celechron` | `Litechron` |
| URL scheme | `celechron` | `litechron` |
| 后台任务 ID | `top.celechron.celechron.backgroundScholarFetch` | `io.github.bno3bno3.litechron.backgroundScholarFetch` |
| MethodChannel | `top.celechron.celechron/ecardWidget` | `io.github.bno3bno3.litechron/ecardWidget` |
| 通知渠道 ID | `top.celechron.celechron.gradeChange`、`.ddlReminder` | `io.github.bno3bno3.litechron.gradeChange`、`.ddlReminder` |
| Pigeon 通道 | `dev.flutter.pigeon.celechron.…` | 改包名后重新生成，自动变为 `dev.flutter.pigeon.litechron.…` |
| 系统日历名 / 描述 | `Celechron课表` / `由Celechron自动同步的浙大课程表` | `Litechron课表` / `由Litechron自动同步的浙大课程表` |
| iCal PRODID | `-//Celechron//Course Calendar 1.0//CN` | `-//Litechron//Course Calendar 1.0//CN` |
| 导出文件前缀 | `celechron_` | `litechron_` |
| 显示名 | `Celechron` | `Litechron` |
| 桌面端二进制 / 产品名 | `celechron` | `litechron` |
| Windows CompanyName / 版权 | `org.cc` | `Litechron` |
| Dart 包名 | `celechron` | `litechron`（第 5 步） |
| 类名 | `CelechronApp`、`CelechronSliverTextHeader`、`CelechronHeader` | `LitechronApp`、`LitechronSliverTextHeader`、`LitechronHeader` |

## 5. 更新、分发与远程数据方案

### 5.1 托管位置

- 仓库：`github.com/bno3bno3/Litechron`（改名前为 `Celechron`）。仓库需公开；GPL 下向他人分发 APK 本来就要求提供源码。
- 静态文件放在仓库 `remote/` 目录，App 经 jsDelivr 读取：`https://cdn.jsdelivr.net/gh/bno3bno3/Litechron@main/remote/<文件>`。
- 本机已验证 jsDelivr 可达。jsDelivr 对分支引用有缓存，更新后需等待一段时间生效；急用时可在 URL 中引用 tag。
- 备选：GitHub Pages 作为纯静态文件托管，或 `raw.githubusercontent.com` 作为二级回退（大陆可达性差）。

### 5.2 版本检查

- 文件 `remote/version.json`：

```json
{
  "version": "1.0.0",
  "build": 1,
  "beta": false,
  "url": "https://github.com/bno3bno3/Litechron/releases/latest"
}
```

- `Fuse.checkUpdate()` 改读该文件，比较逻辑不变；"访问网站"按钮改为打开 `url`。
- 发布流程：改 pubspec 与 Fuse 版本，打 tag，GitHub Releases 上传 APK，更新 `remote/version.json`。
- 若选择"暂不做更新检查"：删除 `Fuse` 的网络逻辑与设置页红点，保留版本展示。

### 5.3 校历配置

- 三级读取：远程 `remote/calendar/<学期>.json` → Hive 缓存 → 内置 `assets/calendar/<学期>.json`。
- 初始数据：从原接口拉取现存学期文件（各入学年份对应学年的 `-1`、`-2`），内容是节次时间与假期的事实数据。
- 每学期需要自己维护一份新文件，这是脱离后的固定成本。
- 原接口不支持 https（探测返回连接失败），保持 `http://`。

### 5.4 签名

- 生成 release keystore，`android/key.properties` 记录路径与口令，`build.gradle` 增加 `signingConfigs.release`。两者都不进仓库。

## 6. Logo 方案

**概念：表盘停在 3:00。** 分针（长）向上、时针（短）向右，两根针以圆心为角构成正向的字母 L。一个圆环、两根线、一个圆点，没有别的元素。既是钟，也是 L。（原方案 12:15 画出来是短竖长横，L 是躺着的，故改为 3:00。）

**候选配色**（先渲染再选）：

| 编号 | 名称 | 底 | 线 | 气质 |
|---|---|---|---|---|
| A | 霜 | 近白 `#FAFAFA` | 深灰 `#1F2937` 或靛蓝 `#4F46E5` | 最轻、最干净，贴合"Lite" |
| B | 墨 | 近黑 `#111827` | 白 | 沉稳大气 |
| C | 靛 | 靛蓝渐变 `#4F46E5` → `#6366F1` | 白 | 醒目，与原版浅蓝拉开距离 |

**制作流程**（不需要手绘）：

1. 用 SVG 写图标源文件 `assets/logo.svg`，关于页用已有依赖 `flutter_svg` 直接渲染，任意尺寸清晰。
2. 用本机 Inkscape（`E:\ProgramFiles\Inkscape\bin\inkscape`）导出 `assets/icon/icon.png`（1024×1024，不透明）和 `assets/icon/icon_foreground.png`（Android 自适应图标前景，图形占中心约 66% 安全区）。
3. `flutter_launcher_icons` 已是依赖，配置改为：

```yaml
flutter_launcher_icons:
  image_path: assets/icon/icon.png
  android: true
  ios: true
  remove_alpha_ios: true
  adaptive_icon_background: "#FAFAFA"
  adaptive_icon_foreground: assets/icon/icon_foreground.png
```

   运行 `dart run flutter_launcher_icons` 生成 Android 各密度 mipmap 与 iOS AppIcon 全部尺寸。
4. `banner.png` 删除，README 只留文字；如需横幅，用同一 SVG 加细体字标 "Litechron" 生成。
5. 中间产物（导出脚本等）放 `temp/`，用完删除。

## 7. 执行计划

每步单独提交，单独可验证。改名期间不夹带功能改动。

### 第 1 步：标识替换（决定并存）

在分支 `rebrand/litechron` 上进行。两个批量替换令牌覆盖绝大多数位置：

- `top.celechron.celechron` → `io.github.bno3bno3.litechron`，连带覆盖 App Group、后台任务 ID、MethodChannel、通知渠道 ID、iOS 四个 Bundle ID。
- `xyz.nosig.celechron` → `io.github.bno3bno3.litechron`，覆盖 Android、macOS、Linux 应用 ID 与 Kotlin `package` 声明。

其余逐项：

| 文件 | 改动 |
|---|---|
| `android/app/src/main/kotlin/xyz/nosig/celechron/` | 两个 Kotlin 文件移到 `io/github/bno3bno3/litechron/` |
| `android/app/src/main/AndroidManifest.xml` | `android:label` 改 `Litechron`；`android:scheme` 改 `litechron` |
| `ios/Runner/Info.plist` | CFBundleDisplayName、CFBundleName、URL scheme 改 `Litechron` / `litechron`；三条权限说明文案顺带改名 |
| `lib/main.dart` | `litechron://ecardpaypage`；`title` 与 `HomePage(title:)`；注释里的 Windows 通知 ID |
| `ECardWidget.kt`、`ECardWidget.swift` | 小组件跳转 `litechron://ecardpaypage`；Swift 侧 `kSecAttrService` 改 `Litechron` |
| `lib/utils/utils.dart`、`lib/database/database_helper.dart` | Keychain `accountName` 改 `Litechron` |
| `lib/model/calendar_to_system.dart` | 日历名与描述两个常量，方法名与注释留到第 3 步 |
| `macos/Runner/Configs/AppInfo.xcconfig`、macOS `project.pbxproj`、`Runner.xcscheme` | 产品名 `litechron`，`celechron.app` → `litechron.app`，版权行 |
| `linux/CMakeLists.txt`、`linux/my_application.cc` | 二进制名 `litechron`，窗口标题 `Litechron` |
| `windows/CMakeLists.txt`、`windows/runner/Runner.rc`、`windows/runner/main.cpp` | 工程名、二进制名、版本资源、窗口标题 |

显示名放在这一步是为了在真机上分清两个 App；其余文案留在第 3 步。Pigeon 通道名随 Dart 包名走，留到第 5 步。

- 验证：`flutter analyze`；`flutter build apk --debug`；装到装有官方 Celechron 的 Android 设备上确认并存、小组件点击跳转 `litechron://ecardpaypage`、后台任务注册成功、通知可弹。iOS 侧本机无法构建，只做静态检查。

### 第 2 步：断线

- 版本检查改读自己的 `remote/version.json`，或按决定删除。
- 校历配置改三级读取，复制现存学期文件到 `assets/calendar/` 与 `remote/calendar/`。
- 贡献者列表改静态名单，删除 GitHub API 请求。
- fork `flutter_workmanager` 到自己名下，pubspec 指向并固定 commit。
- 删除 ICP 备案号与所有 celechron.top 链接。
- 验证：断网启动新装 App 能生成课表；关于页正常。

### 第 3 步：品牌

- 显示名、通知与导出文案、系统日历名、iCal PRODID、导出文件前缀。
- 关于页改为 Litechron，并加"基于 Celechron 二次开发，遵循 GPLv3"及原作者名单。
- 类名 `CelechronApp`、`CelechronSliverTextHeader`、`CelechronHeader` 及 `calendar_to_system.dart` 方法名。
- Logo 按第 6 节生成并替换全部图标。
- README 重写；`CLAUDE.md`、`AGENTS.md` 改 4 处提及并新增"品牌与标识"一节：应用 ID、不得重新引入原项目接口、关于页署名必须保留、设计原则。
- 验证：`flutter analyze`；真机查看图标、关于页、通知文案。

### 第 4 步：版本重置与发布

- pubspec 与 `Fuse` 同步改为 `1.0.0+1`；新增一个测试读取 pubspec 校验 `Fuse.version` 不漂移，避免引入 `package_info_plus`。
- 生成 keystore，配置 release 签名，`flutter build apk --release`。
- 打 `v1.0.0` 标签，发 GitHub Release，写 `remote/version.json`。

### 第 5 步（可选）：Dart 包名

- pubspec `name: litechron`，`lib/` 与 `test/` 共 77 个文件的 `package:celechron/` 改为 `package:litechron/`。
- 重新生成 Pigeon：`dart run pigeon --input lib/pigeon/prompt/flow_message_prompt.dart`，Dart 与 Swift 两侧一起更新。
- 放最后是因为它让与上游合并时冲突最多；若仍打算持续吸收上游的爬虫修复，可以不做。

## 8. 风险与限制

- **iOS 无法在本机验证。** 这台 Windows 机器不能构建 iOS，改动只能靠 Mac 或 CI 验证；上 iOS 还需自己的 Apple 开发者账号、Team ID 与 App Group 注册。
- **校历 JSON 需每学期维护。** 这是独立的固定成本；内置兜底只保证旧学期可用。
- **上游同步变难。** 改名后合并上游会在标识文件与 import 行上冲突。当前 fork 已有意放弃部分上游功能，之后更适合按需 cherry-pick。
- **发布前不可回退的决定：应用 ID。** 一旦分发给他人，再改 ID 等于让用户重装。
- **本地目录改名的副作用。** Claude Code 的项目记忆按路径区分，目录从 `D:\code\Celechron` 改名后记忆目录随之变化。
- 所有中间脚本、导出图放 `temp/`，路径记入 `rubbish.md`，任务结束后清理。

## 9. 待办清单

- [x] 确认应用 ID（2026-09-20）；更新渠道、Dart 包名待确认
- [x] 创建 `rebrand/litechron` 分支
- [x] 第 1 步：Android 标识
- [x] 第 1 步：iOS / macOS 标识（静态替换，未能在本机构建）
- [x] 第 1 步：Linux / Windows 元数据
- [x] 第 1 步：Dart 侧 ID（App Group、Keychain、scheme、任务 ID、渠道）
- [ ] 第 1 步：Android 真机并存验证（暂无设备，已用 aapt 确认 APK 包名为 io.github.bno3bno3.litechron、label 为 Litechron）
- [x] 第 2 步：版本检查改读 jsDelivr 上的 remote/version.json（2026-09-20）
- [x] 第 2 步：校历配置原接口 → Hive → assets/calendar 兜底，内置 2022-2023-1 至 2026-2027-1 共 9 份（2026-09-20）
- [x] 第 2 步：贡献者静态名单，删除 github_service.dart（2026-09-20）
- [ ] 第 2 步：workmanager fork
- [x] 第 2 步：删除 ICP 与 celechron.top 链接（2026-09-20）
- [ ] 第 3 步：文案与显示名
- [ ] 第 3 步：关于页署名
- [ ] 第 3 步：类名与方法名
- [ ] 第 3 步：Logo 候选、选定、生成图标
- [ ] 第 3 步：README、CLAUDE.md、AGENTS.md
- [ ] 第 4 步：版本重置与校验测试
- [ ] 第 4 步：release 签名与构建
- [ ] 第 4 步：v1.0.0 标签、Release、version.json
- [ ] 第 5 步（可选）：Dart 包名与 Pigeon 重新生成
- [ ] 清理 temp/ 与 rubbish.md，归档本文档
