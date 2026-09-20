# CLAUDE.md

This file gives Claude Code the project context needed to work safely in this repository.

## Project Overview

Litechron is a Flutter/Dart cross-platform app for Zhejiang University students, forked from Celechron and rebranded so it can be installed alongside the official app. It combines schedule viewing, course and exam data, task/DDL management, GPA and grade display, homework reminders from Learning in ZJU, calendar export/sync, and platform widgets/live activities.

The app is stateful and data-heavy. Most features depend on persisted Hive data, secure credentials, GetX global state, and network scraping of ZJU services. Prefer small, behavior-preserving changes unless the requested task explicitly calls for a broader refactor.

本app的设计理念是简洁、简约，在设计项目新功能、新模块的界面时应当在与原其他界面风格相同的条件下遵从这一理念。

## Tech Stack and Commands

- Flutter/Dart app, SDK constraint in `pubspec.yaml`: `>=3.0.0`.
- State and dependency lookup: GetX (`Get.put`, `Get.find`, `Rx`, `Obx`, controller lifecycle).
- Local persistence: Hive plus custom adapters in `lib/database/adapters/`.
- Credential and background-task flags: `flutter_secure_storage`.
- Background refresh: `workmanager` from a custom Git fork (originally by Celechron) referenced in `pubspec.yaml`.
- Notifications: `flutter_local_notifications`.
- Native bridge/widget data transfer: Pigeon files under `lib/pigeon/`, plus iOS/Android platform code.

Useful commands:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

There is no obvious dedicated test directory in the current tree, so use `flutter analyze` as the baseline check for most code changes. Run more targeted app/platform checks when changing background work, notifications, native widgets, Pigeon, or platform project files.

## Repository Map

- `lib/main.dart`: app startup, Hive initialization, `DatabaseHelper` creation, GetX global object injection, app routes, notification setup, App Links handling, Android system bar styling, and startup refresh.
- `lib/model/`: core domain models such as `Scholar`, `Semester`, `Task`, `Period`, `Course`, `Grade`, `Exam`, `Todo`, and calendar export/sync helpers.
- `lib/database/`: `DatabaseHelper` and Hive adapters. This layer owns boxes, defaults, secure credential storage, cache storage, and migrations.
- `lib/http/`: ZJU network integration and scraping. `Spider` is the interface; `UgrsSpider` and `GrsSpider` aggregate unified auth, undergraduate/graduate services, calendar config, grades, courses, exams, and homework.
- `lib/http/zjuServices/`: service-specific HTTP clients for unified auth, ZDBK, GRS, Learning in ZJU, e-card, and related endpoints.
- `lib/page/`: UI pages and GetX controllers. Major sections are Flow, Calendar, Task, Scholar, Option, and Search.
- `lib/algorithm/arrange.dart`: scheduling/allocation algorithm used by Flow.
- `lib/worker/`: background refresh, update checking, e-card widget sync, and flow/widget messaging helpers.
- `lib/pigeon/`: Flutter/native message DTOs and generated bridge code.
- `android/`, `ios/`, `macos/`, `linux/`, `windows/`: platform projects.
- `assets/`: app assets, including logo.

## Core Runtime Flow

1. `main()` initializes Hive and `DatabaseHelper`, then opens/registers all persistence layers.
2. `main()` injects global state with GetX tags:
   - `db`: `DatabaseHelper`
   - `scholar`: `Rx<Scholar>`
   - `taskList`: `RxList<Task>`
   - `taskListLastUpdate`: `Rx<DateTime>`
   - `flowList`: `RxList<Period>`
   - `flowListLastUpdate`: `Rx<DateTime>`
   - `option`: `Option`
   - `fuse`: `Rx<Fuse>`
3. `LitechronApp` builds a `GetCupertinoApp` with Chinese locale, root `HomePage`, and `/ecardpaypage`.
4. If a saved `Scholar` is logged in, startup shows cached data first, then asynchronously logs in and refreshes remote academic data.
5. `HomePage` hosts five main tabs: Flow, Calendar, Task, Scholar, and Option. Search is kept as a cached extra page.

## Data and State Rules

- `Scholar` is the central academic aggregate. It owns login state, semesters, grades, GPA, homework todos, special dates, and refresh timestamps.
- `Scholar.login()` selects the spider implementation:
  - username `3200000000`: `MockSpider`
  - undergraduate-style account: `UgrsSpider`
  - graduate-style account: `GrsSpider`
- `Scholar.refresh()` calls `Spider.getEverything()`, merges partial successes, preserves existing local data on failed sections, recalculates GPA, and persists through `DatabaseHelper`.
- Async refresh: when the `asyncRefresh` option is on and callers pass `onPartialUpdate` to `Scholar.refresh()`, each completed top-level fetch is merged into memory immediately (semesters/special dates only after all their source fetches succeed, practice scores only at the end); the final full merge, persistence, and error reporting still run exactly as in sync mode. Background refresh never passes the callback and stays synchronous.
- `Option` stores reactive user settings. `OptionController` writes changes back to Hive and sometimes mirrors flags into secure storage for background tasks.
- `TaskController` owns task status transitions, fixed schedule rollover, sorting, and task persistence.
- `FlowController` owns generated work blocks, live progress accrual, synchronization back to tasks, persistence throttling, and iOS widget/live activity transfer.
- `CalendarController` combines `Scholar.periods` with fixed tasks to produce daily calendar events.

When editing controllers, preserve the existing pattern: mutate the shared GetX object, call `.refresh()` when mutating contained objects in place, and persist through `DatabaseHelper` when user-visible state should survive restart.

## Persistence Rules

- Be very careful when changing Hive-backed models or adapters.
- Do not renumber existing `@HiveType(typeId: ...)` or `@HiveField(...)` values.
- Do not reorder adapter read/write fields unless you also implement a compatible migration.
- `DatabaseHelper.init()` registers all adapters before opening boxes. New persisted types must be registered there.
- Credentials (`username`, `password`) live in `flutter_secure_storage`, not plain Hive fields. Do not store secrets in logs, fixtures, docs, or commits.
- `originalWebPageBox` is a cache for remote pages. Do not treat cached remote content as canonical user data.

## Network and Auth Rules

The ZJU scraping layer is brittle by nature. Preserve current behavior unless a task specifically targets this area.

- `ZjuAm.getSsoCookie()` performs unified auth and RSA password encryption.
- `UgrsSpider` and `GrsSpider` manually manage login, cookies, timeout behavior, retry-after-login, and partial fetch errors.
- `getEverything()` returns `Tuple7` (aliased as `EverythingTuple` in `spider.dart`) with login errors, fetch errors, semesters, grades, major GPA data, special dates, and todos. It also accepts an optional `onProgress` callback (async refresh) that reports accumulated partial data after each top-level fetch. Keep this contract stable unless all callers are updated.
- Partial refresh failures intentionally preserve previously cached local data. Avoid clearing existing academic data merely because one remote service fails.
- Timeout values, user agent, retryable error strings, and cookie invalidation checks affect real login reliability.

## UI and Controller Patterns

- UI is mostly Cupertino-styled, with Material icons used where needed.
- Controllers are created with GetX and often rely on global tags instead of constructor injection.
- Prefer following existing page/controller structure in `lib/page/<feature>/`.
- Avoid moving business logic into widgets when an existing controller already owns that behavior.
- Keep text and UI behavior consistent with the existing Chinese-first app experience.
- Some terminal output may show Chinese text as mojibake; write new project documentation as normal UTF-8.

## Scheduling and Calendar Rules

- `Task` has three types: real DDL (`deadline`), fixed schedule (`fixed`), and historical fixed schedule (`fixedlegacy`).
- `Period` has five types: class, exam/test, user schedule, virtual free slot, and Litechron-generated flow block.
- `FlowController.generateNewFlowList()` uses task deadlines, user allowed work times, blocking fixed schedules, and academic periods to produce flow blocks.
- `FlowController.walkFlowList()` is responsible for pruning expired periods, syncing DDL descriptions, adding upcoming classes/fixed schedules, and saving only meaningful changes.
- `Semester.periods` is cached. Any mutation that changes sessions, exams, grades, calendar config, or derived course state must invalidate that cache.
- Calendar export/sync behavior is in `lib/model/calendar_to_ical.dart` and `lib/model/calendar_to_system.dart`.

## Background, Notifications, and Native Integration

- Background refresh entry point is `callbackDispatcher()` in `lib/worker/background_app_refresh.dart` and must remain annotated with `@pragma('vm:entry-point')`.
- Background tasks read credentials and option flags directly from secure storage. If option key names change, update both foreground settings and background refresh.
- Notification channels/IDs are part of user-visible behavior; avoid churn unless needed.
- iOS widget/live activity data is transferred through Pigeon DTOs in `lib/pigeon/` and platform files under `ios/`.
- Android e-card widget behavior touches `android/app/src/main/kotlin/...` and XML widget metadata.
- Do not casually edit entitlements, manifests, Gradle/CocoaPods settings, or generated registrant files.

## Generated or Fragile Files

Treat these as generated or high-risk unless the task explicitly targets them:

- `lib/pigeon/flow_messenger.dart`
- platform generated plugin registrants
- `.flutter-plugins-dependencies`
- `build/`
- platform project files such as Xcode project metadata, entitlements, manifests, and Gradle wrapper/config
- Hive adapters, unless updating persistence intentionally

If Pigeon interfaces change, regenerate the corresponding Dart/native outputs and verify both Flutter and native sides.

## Brand and Identifiers

- App name is **Litechron**. The Dart package name is still `celechron` (imports use `package:celechron/`); do not treat that as a user-visible name.
- Application ID / bundle ID / App Group base is `io.github.bno3bno3.litechron`. URL scheme is `litechron`. Keychain service name is `Litechron`. System calendar name is `Litechron课表`. These differ from official Celechron on purpose so both apps coexist; never revert them.
- Do not reintroduce upstream endpoints: `api.celechron.top` (update check), `api.github.com/repos/Celechron/...` (contributors), or `celechron.top` links. Update check reads `remote/version.json` from this repository via jsDelivr (`Fuse.checkUpdateUrl`).
- Semester calendar config still comes from `calendar.celechron.top` with fallbacks to Hive cache and bundled `assets/calendar/<semester>.json`. Add a new bundled file each semester.
- The About page must keep the line stating the project is derived from Celechron under GPLv3. The ICP record number of the upstream project must not be re-added.
- Logo is `assets/logo.svg` (rendered with `flutter_svg`); launcher icons are generated from `assets/icon/` via `flutter_launcher_icons`. Keep the visual language minimal: one ring, two hands, one dot.

## Security and Privacy

- Never commit real student IDs, passwords, cookies, CAS tickets, secure storage dumps, raw private ZJU responses, or personally identifiable academic data.
- Use `MockSpider` or sanitized fixtures for examples.
- Avoid adding debug prints that expose credentials, cookies, response bodies, grades, course records, or homework details.
- Keep `.claude/settings.local.json` untouched unless the user explicitly asks to change local Claude settings.
- 在你要创建一些脚本或者记录一些东西的时候，要把他们放在本目录的temp文件夹下面，如果没有就自己创建。不能放在项目之外的地方
- 在你结束任务之前，要整理一下过程中你产生的中间文件（不止是在这个项目目录中的，也包括你放在c盘等其他任意地方的，但不包括与项目功能等相关的文件。换言之，就是删掉不影响项目使用的文件），如脚本、日志等各种文件，并将其绝对路径写入`rubbish.md`。然后在给你的该任务完成后把他们删掉（依照你写入的rubbish.md），然后再清掉rubbish.md中相应的部分。如果rubbish.md里面还有其他的文件，就逐一看看他们删掉是否影响项目使用，如果不影响，仅仅作为中间工具或者是一些其他的，就把他们也删掉好了，然后再清空rubbish.md。

## Current Notes

- The repository currently has an untracked `.claude/` directory. Do not modify or remove it during normal project work.
- `README.md` appears with encoding issues in this shell, but the intended description is a ZJU-focused time manager with schedule overview, timetable, DDL assistant, and grade query features.
- The custom `workmanager` Git dependency is important for background behavior; upgrading or replacing it requires platform testing.
