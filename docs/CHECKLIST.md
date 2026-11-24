# QuickSnap 功能与实施进度清单

> 约定：每完成一个功能或里程碑，立即将对应条目由 `- [ ]` 更新为 `- [x]`，便于跨会话接续与核对。

## Stage 0：工程初始化与文档底座
- [x] 持久化实施计划书（`docs/PLAN.md`）与进度清单（`docs/CHECKLIST.md`）
- [x] 创建 SwiftPM 工程配置（`Package.swift`）与 Bundle 配置（`Resources/Info.plist`）
- [x] 建立 GEB L1 根文档（`GEMINI.md`）

## Stage 1：核心逻辑层（`QuickSnapCore`）
- [x] `SettingsStore`：保存目录、导出格式、提示音、全屏自动保存、快捷键持久化
- [x] `HotkeyManager`：Carbon 免辅助功能权限全局快捷键注册与回调分发
- [x] `AnnotationModels`：6 种标注工具模型、撤销/重做历史栈、选区边界与手柄计算
- [x] `AnnotationRenderer`：统一 CoreGraphics 矢量绘制与低内存降采样马赛克缓存
- [x] `ScreenCaptureService`：ScreenCaptureKit 多屏 Retina 捕获与屏幕录制权限检测/跳转
- [x] `OCRService`：Vision 离线中英文混排文字识别与行序拼接
- [x] `ImageExporter`：Retina 高清裁剪合成、剪贴板写入与 PNG/JPEG 文件保存
- [x] `QuickSnapCore` L2 文档（`GEMINI.md`）与编译通过（`swift build`）

## Stage 2 & 3：菜单栏壳、截图画布与面板（`QuickSnap`）
- [x] `App` 入口与菜单栏常驻（`main.swift`、`AppDelegate.swift`：区域/OCR/全屏/设置/权限/退出）
- [x] `CaptureCoordinator`：多屏会话协调、防重入锁、退出即时释放窗口与位图内存
- [x] `CaptureOverlayWindow`：跨 Space / 全屏应用的无边框遮罩窗口
- [x] `CaptureCanvasView`：屏幕定格、挖空遮罩、实时像素尺寸标签、8 向调整手柄
- [x] `CaptureCanvasView` 标注交互：矩形、椭圆、箭头、画笔、惰性马赛克、行内文字输入、快捷键
- [x] `FloatingToolbarView`：智能防越界浮动工具栏（标注切换、颜色/线宽、撤销重做、OCR、保存、复制、取消）
- [x] `OCRResultWindow`：轻量 OCR 结果悬浮窗（加载态、文本微调、置顶切换、一键复制）
- [x] `PreferencesWindow`：偏好设置窗（保存目录、格式、快捷键录制、权限实时检测）
- [x] `ToastWindow`：轻量自动销毁 HUD 操作反馈提示
- [x] 应用层 L2 文档与完整工程编译通过（`swift build`）

## Stage 4a：自动化测试与端到端验证
- [x] `SelectionAndHistoryTests`：选区几何计算、撤销/重做栈、配置持久化测试
- [x] `ExporterAndOCRTests`：Retina 2x 标注合成导出与中英文图像端到端 Vision OCR 测试
- [x] `swift test` 全部通过

## Stage 4b：图标、应用包与 DMG 打包交付
- [x] `generate_icon.swift`：生成原生高清 `Resources/AppIcon.icns`
- [x] `build_app.sh`：Release 编译、组装 `dist/QuickSnap.app` 与本地代码签名
- [x] `build_dmg.sh`：构建包含拖拽安装替身的 `dist/QuickSnap.dmg`
- [x] 实测校验：`codesign` 签名有效、DMG 结构完整且体积 < 5 MB、待机进程内存正常且稳定运行
- [x] 全项目 GEB L1/L2/L3 文档一致性终检

## Stage 5：工具栏重构与固定贴图（Pin）
- [x] 重构 `FloatingToolbarView`（自定义图标/胶囊按钮、悬停反馈、修复中文下文字图标显示为“格式”、圆点线宽选择、动态宽度防裁切）
- [x] 新增 `SelectionMath.appKitGlobalFrame` 多屏坐标转换与单元测试
- [x] 新增 `PinnedImageWindow`（原位桌面悬浮贴图：拖拽、滚轮缩放、悬停操作栏、右键菜单、透明度与关闭释放内存）
- [x] 接入 `CaptureCanvasView`（`⌘P` 快捷键与工具栏固定按钮）、`CaptureCoordinator` 与菜单栏「关闭所有固定贴图」
- [x] 测试通过、重建 `dist/QuickSnap.dmg` 并重新安装启动 `/Applications/QuickSnap.app`

## Stage 6：工具栏全图标化、指针修复、交互保存与贴图拖拽缩放修复
- [x] 修复鼠标悬停工具栏仍显示十字准星的问题（切换为箭头指针）
- [x] 重构 `FloatingToolbarView` 为全图标设计（无中文/文字标签，含固定、OCR、保存、取消、复制图标按钮）
- [x] 改造保存逻辑：点击保存或 `⌘S` 弹出原生 `NSSavePanel` 选择路径与文件名后保存（截图画布与固定贴图同步支持）
- [x] 修复并增强 `PinnedImageWindow`：移除吞掉拖拽事件的 `NSImageView`，支持直接左键拖动移动、四角拖拽缩放、滚轮缩放与触控板双指捏合缩放
- [x] 运行测试、重建 `dist/QuickSnap.dmg` 并重新安装启动 `/Applications/QuickSnap.app`
- [x] 修复 `PinnedImageWindow` 首次点击激活拦截问题（`acceptsFirstMouse = true`），单次按住即可直接拖动、缩放与点击悬停按钮
- [x] 创建本机固定代码签名证书 `QuickSnap Code Signing` 并改造 `build_app.sh` 自动优先使用（无证书时回退 `-`）
- [x] 使用固定证书重编签名、校验 `designated` 身份要求、重建 `dist/QuickSnap.dmg` 并重装启动 `/Applications/QuickSnap.app`

## Stage 7：V2 功能迭代（窗口识别、放大镜取色、自启、序号荧光笔、仓库文档）
- [x] V2-1：窗口自动识别与悬停高亮、单击整窗捕获（`DetectedWindow`、`SelectionMath.quartzRectToDisplayLocal`、`CaptureCanvasView`）
- [x] V2-2：局部像素放大镜与 `HEX / RGB` 取色器（`PixelSampler`、放大镜浮窗、`Shift` 切换格式、`C` 复制色值）
- [x] V2-3：开机自启动开关（`LaunchAtLoginService` 基于 `SMAppService` + 偏好设置开关）
- [x] V2-4：序号标注（①②③ 自动递增/撤销回退）与半透明荧光笔标注（`AnnotationModels`、`AnnotationRenderer`、`CaptureCanvasView`）
- [x] V2-5：补充仓库 `README.md` 与 `.gitignore`（含私钥防误提交规则）及 GEB 文档同步
- [x] V2 验证：补充单元测试并全部通过、固定证书签名重建 `dist/QuickSnap.dmg` 并重装启动 `/Applications/QuickSnap.app`

## Stage 8：偏好设置重构与截图文件名命名规则
- [x] 新增截图文件名命名规则引擎（`FilenamePreset`、`FilenameFormatter`、`SettingsStore.filenameTemplate` 与非法字符清洗）
- [x] 统一接入 `ImageExporter`（全屏自动保存）与 `InteractiveSaver`（原生保存弹窗默认文件名）
- [x] 重构 `PreferencesWindow` 为左侧分类导航 + 右侧卡片详情布局，内置模板预设、一键插入占位符与实时文件名预览
- [x] 补充命名规则与配置持久化单元测试、全部测试通过、固定证书签名重建 `dist/QuickSnap.dmg` 并重装启动 `/Applications/QuickSnap.app`
- [x] 视觉精修 `PreferencesWindow`：移除暗灰底色，改用半透明 `.sidebar` 侧边栏、透明无边框标题栏、右侧 Switch 开关与原生浅色/深色自适应卡片
- [x] 全透原生毛玻璃重绘 `PreferencesWindow`（`.sidebar` + `.popover` 双层 behindWindow 毛玻璃、透明无底窗口、高光细描边玻璃卡片与极简 SF Symbol 导航）
