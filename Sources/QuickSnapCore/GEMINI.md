# QuickSnapCore/
> L2 | Parent: ../../GEMINI.md

Member list
SettingsStore.swift: UserDefaults 配置持久化中心，管理保存路径、导出格式、文件名模板（FilenameFormatter）、提示音与 Carbon 快捷键模型
HotkeyManager.swift: Carbon 全局快捷键引擎，无需辅助功能权限即可注册与分发截图热键
AnnotationModels.swift: 标注工具（含荧光笔与序号）、历史栈及选区/窗口几何坐标转换（SelectionMath）
AnnotationRenderer.swift: 实时画布与离屏导出共用的 CoreGraphics 渲染器，含降采样马赛克与序号圆章绘制
PixelSampler.swift: 零重复分配像素取色缓存器，提供 HEX 与 RGB 采样格式化
LaunchAtLoginService.swift: 基于 ServiceManagement（SMAppService）的开机自启动控制服务
ScreenCaptureService.swift: ScreenCaptureKit 多屏 Retina 捕获、前台窗口识别与屏幕录制权限检测跳转
OCRService.swift: Apple Vision 离线中英文混排文字识别及按行序拼接服务
ImageExporter.swift: 原图裁剪、矢量标注合成、剪贴板写入与按命名规则保存 PNG/JPEG 文件

[PROTOCOL]: Update this header on change, then check GEMINI.md
