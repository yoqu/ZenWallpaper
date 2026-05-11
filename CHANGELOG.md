# Changelog

记录 ZenWallpaper 每个发布版本的变化。版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [1.1.0] - 2026-05-11

### 新增 Added
- **多显示器模式**：在「设置 → 显示器」里可在三种模式间切换。
  - 统一壁纸：所有显示器共用同一张。
  - 每屏独立：每块显示器各自指派，缩略图右键即可选择目标屏。
  - 仅主屏：只设置主屏，其他显示器保留系统壁纸。
- **每屏指派持久化**：用 CG 显示 UUID 做主键，重启或热插拔后绑定关系自动恢复（`DisplayAssignmentStore` / `DisplayIdentity`）。
- **按屏幕比例选图**：生成接口会根据当前屏幕宽高比挑选最接近的后端尺寸（`WallpaperScreenPolicy`），16:10、16:9、超宽屏都不再被拉伸。
- 云端作品筛选也按当前屏幕比例过滤，避免出现明显不匹配的作品。

### 改进 Changed
- **云端作品去重**：点击云端作品下载并设置壁纸时，若本地缓存已有同一作品（按 `remoteWorkId` 匹配），直接复用本地副本，不再重复下载、不再多塞一条历史记录。
- 模块拆分：把 `PromptComposer`、`WallpaperCatalog`（心情 / 风格清单）从 `Models.swift` 中独立出来，便于复用与单测。
- 一次性清理迁移期残留：启动时移除 SwiftUI 旧模块路径写下的 `NSWindow Frame` 默认值，修复菜单栏首次点击的偶发崩溃。

### 测试 Tests
- 新增 `WallpaperCatalogTests` 覆盖心情 / 风格清单的稳定性。

---

## [1.0.0] - 2026-05-08

ZenWallpaper 首个开源发布版。

- macOS 菜单栏常驻 App。
- 心情面板、风格预设、农历 / 公历日期、补充提示词拼成 prompt 并生成壁纸。
- 历史记录缓存、自动换壁纸调度、与 qushenma 后端对接。
- 中英双语 UI 自动跟随系统语言。

[1.1.0]: https://github.com/yoqu/ZenWallpaper/releases/tag/v1.1.0
[1.0.0]: https://github.com/yoqu/ZenWallpaper/releases/tag/v1.0.0
