# 发布流程

Litechron 通过 GitHub Releases 分发 Android APK。App 每天启动时读取本仓库 `main` 分支上的
`remote/version.json`（经 jsDelivr），发现新版本后提示用户，点"前往下载"打开 Release 页面，
用户下载 APK 覆盖安装，数据保留。

## 一次性准备

- 签名密钥 `android/litechron-release.jks` 与口令文件 `android/key.properties`
  都不在仓库里，请离线备份。所有版本必须用同一把密钥签名，换密钥后老用户无法覆盖安装，只能卸载重装并丢失数据。
- 仓库必须公开，jsDelivr 才能读到 `remote/version.json`。

## 每次发版

1. **改版本号**，两处必须一致，`flutter test` 会校验：

   ```
   pubspec.yaml            version: 1.0.1+2
   lib/worker/fuse.dart    version = [1, 0, 1];  build = 2;
   ```

   加号后面的构建号必须严格递增，否则 Android 不认为是升级。

2. **构建**：

   ```
   flutter test
   flutter build apk --release
   ```

   产物在 `build/app/outputs/flutter-apk/app-release.apk`，重命名为 `Litechron-v1.0.1.apk`。

3. **提交、打标签、推送**：

   ```
   git commit -am "发布 1.0.1"
   git tag v1.0.1
   git push origin main v1.0.1
   ```

4. **GitHub Release**：在仓库 Releases 页新建 Release，选择标签 `v1.0.1`，上传 APK，发布。

5. **更新 `remote/version.json`**，在 Release 发布之后再做，否则用户会先收到提示却下载不到：

   ```json
   {
     "version": "1.0.1",
     "build": 2,
     "beta": false,
     "url": "https://github.com/bno3bno3/Litechron/releases/latest"
   }
   ```

   提交并推送到 `main`。

6. **刷新 jsDelivr 缓存**（可选，不做则最长十几小时后生效）：

   ```
   https://purge.jsdelivr.net/gh/bno3bno3/Litechron@main/remote/version.json
   ```

## 字段说明

| 字段 | 作用 |
|---|---|
| `version` / `build` / `beta` | 与 App 内版本比较，决定是否提示 |
| `url` | "前往下载"打开的页面。GitHub 在国内访问慢时可换成镜像或其他托管地址，不用发新版 |

## 用户侧体验

- 弹窗"更新可用"，点"前往下载"打开 Release 页面，下载 APK 后安装覆盖，数据保留。
- 设置页"前往项目网站"一行在有新版本时显示红点和"有新版本可用"，点击同样打开下载页。
- 自动检查每 24 小时一次。

## 后续

应用内直接下载并安装的实现保存在分支 `feature/in-app-update`（已在模拟器验证到下载进度环节，
安装环节待真机验证），需要时可合并启用。
