# QuickSnap 实施计划书

## 一、产品定位与技术目标

- **目标平台**：macOS 14.0+ 原生菜单栏应用（`LSUIElement = true`，不占 Dock 栏）
- **核心能力**：区域选框截图、全屏截图、6 种基础标注工具、离线中英文 OCR 文字识别、偏好设置、`.dmg` 拖拽安装
- **性能原则**：轻量（DMG < 5 MB）、低内存（待机态约 15–25 MB，截图态用完即毁释放位图）、高帧率流畅交互

## 二、技术架构（零第三方依赖）

采用双 Target SwiftPM 工程结构，便于 `QuickSnapTests` 直接测试核心逻辑：

1. **`QuickSnapCore`（核心库）**
   - `SettingsStore.swift`：基于 `UserDefaults` 的持久化配置（保存目录、PNG/JPEG 格式、快捷键、提示音等）
   - `HotkeyManager.swift`：基于 `Carbon.HIToolbox` 的全局热键管理（无需辅助功能权限）
   - `AnnotationModels.swift`：标注工具、颜色、线宽、撤销/重做历史栈与选区数学计算（`SelectionMath`）
   - `AnnotationRenderer.swift`：画布实时预览与离屏高清导出共用的 CoreGraphics 渲染器（含降采样马赛克底图缓存与翻转文字绘制）
   - `ScreenCaptureService.swift`：基于 `ScreenCaptureKit` 的多屏 Retina 原生截图与权限检测
   - `OCRService.swift`：基于 Apple `Vision` 的离线中英混排文字识别与按行排版
   - `ImageExporter.swift`：原图裁剪、矢量标注高清合成、剪贴板写入与 PNG/JPEG 文件保存

2. **`QuickSnap`（应用层）**
   - `App/main.swift` & `AppDelegate.swift`：应用入口、菜单栏常驻图标、全局热键绑定、权限引导
   - `CaptureUI/CaptureCoordinator.swift`：多屏截图会话协调、防重入锁、退出即彻底释放位图与窗口内存
   - `CaptureUI/CaptureOverlayWindow.swift`：跨全屏/多桌面无边框遮罩 `NSPanel`
   - `CaptureUI/CaptureCanvasView.swift`：翻转坐标系画布（选区框选、8 向手柄调整、6 种标注、惰性马赛克、行内文字编辑、快捷键响应）
   - `CaptureUI/FloatingToolbarView.swift`：智能贴边浮动工具栏（自动避让屏幕边界）
   - `Panels/OCRResultWindow.swift`：按需创建的轻量 OCR 结果悬浮窗（编辑、置顶、一键复制）
   - `Panels/PreferencesWindow.swift`：按需创建的轻量偏好设置窗（保存路径、格式、快捷键录制、权限状态）
   - `Panels/ToastWindow.swift`：自动淡出销毁的轻量 HUD 提示

3. **构建与打包（`scripts/`）**
   - `generate_icon.swift`：CoreGraphics 生成多尺寸应用图标并转为 `Resources/AppIcon.icns`
   - `build_app.sh`：Release 编译 + 组装 `dist/QuickSnap.app` + `codesign` 签名验证
   - `build_dmg.sh`：使用 `hdiutil` 生成包含 `QuickSnap.app` 与 `/Applications` 替身的压缩 `dist/QuickSnap.dmg`

## 三、分阶段里程碑

- **Stage 0**：工程初始化与计划/清单持久化（`docs/PLAN.md`、`docs/CHECKLIST.md`、`Package.swift`、`GEMINI.md`）
- **Stage 1**：实现 `QuickSnapCore` 核心层并编译通过
- **Stage 2 & 3**：实现 `App`、`CaptureUI` 与 `Panels` 交互层并编译通过
- **Stage 4a**：完成单元测试与端到端合成图 OCR / Retina 导出验证（`swift test` 全绿）
- **Stage 4b**：完成图标生成、`.app` 组装、`dist/QuickSnap.dmg` 打包与运行时内存/结构验证

## 四、Stage 5：工具栏视觉重构与固定贴图（Pin）

- **重构 `FloatingToolbarView`**：
  - 使用自定义几何 `"T"` 模板图标替代随中文系统本地化为「格式」的 `textformat` 符号
  - 构建统一风格的自定义控件（`ToolbarIconButton`、`ToolbarPillButton`、`ColorSwatchButton`、`StrokeDotButton`），全面支持 `NSTrackingArea` 悬停态与统一暗色玻璃质感
  - 用圆点线宽按钮（`5pt / 8.5pt / 12pt`）替代原生灰色「细/中/粗」按钮；使用 `rootStack.fittingSize` 动态计算工具栏尺寸，彻底消除固定宽度裁切
- **新增固定贴图（`PinnedImageWindow` / `PinManager`）**：
  - 支持将选区及标注结果原位固定到桌面悬浮窗（`NSWindow.Level.floating`）
  - 支持鼠标直接拖拽移动、滚轮 `0.25x–3.0x` 等比缩放、悬停微工具栏（复制/OCR/关闭）、右键菜单（复制/保存/OCR/还原大小/透明度切换/关闭）、快捷键（`Esc`、`⌘W`、`⌘C`、`⌘S`、`⌘0`）与关闭即时释放内存
  - `CaptureCoordinator`、`CaptureCanvasView`（`⌘P`）与菜单栏「关闭所有固定贴图」联动

## 五、Stage 6：工具栏全图标化、指针修复、交互保存与贴图拖拽缩放修复

- **光标指针修复**：`CaptureCanvasView.updateCursor(at:)` 与 `FloatingToolbarView` 统一在工具栏区域内强制切换为 `NSCursor.arrow`（不再保留十字准星），行内文本编辑区切换为 `NSCursor.iBeam`。
- **全图标化工具栏**：移除 `ToolbarPillButton` 及所有按钮中文/文字显示（OCR、复制改为纯图标按钮，仅保留悬停 Tooltip）。
- **交互式保存路径**：新增 `InteractiveSaver`（基于原生 `NSSavePanel`），在截图画布和固定贴图点击保存或按 `⌘S` 时弹出系统保存对话框选择目录与文件名，并记住上次保存目录。
- **固定贴图可自由移动与缩放**：移除拦截鼠标事件的 `NSImageView`，改由 `PinnedImageContentView` 直接绘制 `CGImage`；左键主体调用 `window.performDrag(with:)` 流畅拖拽移动，支持四角拖拽等比缩放、滚轮缩放、触控板双指捏合缩放、缩放比例提示浮标及悬停保存按钮。

## 六、持久化代码签名（免重复授权 TCC）

- 在本机钥匙串生成自签名代码签名证书 `QuickSnap Code Signing`（通用名，不含个人信息，私钥仅留本机钥匙串）。
- `scripts/build_app.sh` 自动按顺序选择签名身份：`CODESIGN_IDENTITY` → `QuickSnap Code Signing` → 临时签名 `-`；固定签名后 `designated` 要求绑定 `identifier "com.quicksnap.app"` 与证书指纹而非 `cdhash`，覆盖升级后屏幕录制权限持久保留。

## 七、Stage 7（V2 增强迭代）

- **V2-1 窗口自动识别**：利用 `CGWindowListCopyWindowInfo` 按前台 Z 序采集普通窗口矩形，经 `SelectionMath.quartzRectToDisplayLocal` 映射至各显示器翻转坐标系；框选前悬停自动挖空高亮窗口边框与名称，单击直接捕获整窗。
- **V2-2 局部放大镜与取色器**：新增 `PixelSampler` 缓存 `CGImage` 像素数据，在框选/调整期显示 `17×12` 像素级放大镜卡片与中心瞄准框；支持 `Shift` 切换 `HEX / RGB` 格式，按 `C` 键复制当前色值。
- **V2-3 开机自启动**：新增 `LaunchAtLoginService`（基于系统 `SMAppService.mainApp`），在偏好设置顶部提供「登录时自动启动 QuickSnap」开关。
- **V2-4 序号与荧光笔标注**：新增 `.highlighter`（半透明荧光笔轨迹）与 `.stepNumber`（点击即生成的①②③自动递增序号圆章，支持撤销/重做自动回退编号）。
- **V2-5 仓库文档与防泄漏配置**：补充 `README.md` 与 `.gitignore`（排除 `.build/`、`dist/` 及私钥证书文件）。

## 八、Stage 8：偏好设置重构与截图文件名命名规则

- **截图文件名命名规则引擎**（`FilenamePreset` / `FilenameFormatter`、`SettingsStore.filenameTemplate`）：
  - 支持 `{yyyy}`、`{MM}`、`{dd}`、`{HH}`、`{mm}`、`{ss}`、`{W}`、`{H}`、`{unix}` 占位符与 4 套快捷预设
  - 自动清洗非法文件名字符（`/`、`\`、`:` 等）并剥离多余扩展名后缀，空模板自动回退默认时间戳
  - 统一接入 `ImageExporter`（全屏自动保存）与 `InteractiveSaver`（原生 `NSSavePanel` 默认文件名）
- **偏好设置界面重构**（`PreferencesWindow`）：
  - 采用 macOS 原生双栏结构（左侧分类导航 + 右侧卡片分组：`通用`、`保存与命名`、`快捷键`、`关于与提示`）
  - 内置命名预设选择、可点击一键插入的占位符胶囊标签、以及实时文件名预览条

## 九、Stage 9：消除截图卡死与快捷键失灵隐患

- **屏幕捕获非阻塞超时保护**（`ScreenCaptureService` / `AsyncTimeout`）：使用 `OSAllocatedUnfairLock` + 竞态计时器封装 4 秒非阻塞超时，防止系统休眠唤醒或锁屏后 `ScreenCaptureKit` 挂死导致无限等待。
- **协调器自愈状态机**（`CaptureCoordinator`）：以代数标识（`captureGeneration`）与 `preparingSince` 取代布尔锁；若超过 1.5 秒未完成或再次触发时存在旧遮罩窗口，自动取消旧请求并复位，杜绝永久卡死。
- **高可靠热键与系统生命周期联动**（`HotkeyManager` / `AppDelegate`）：
  - 热键注册由 `GetApplicationEventTarget()` 升级为 `GetEventDispatcherTarget()`，并支持快捷键录制期间临时挂起/恢复，防止按键冲突。
  - 启动 2.5 秒后自动补注册（兜底开机自启过早窗口），并监听 `willSleep`、`didWake`、`screensDidWake`、`sessionDidBecomeActive`、`didChangeScreenParameters` 与 `com.apple.screenIsUnlocked` 自动复位状态与静默重注册热键。
