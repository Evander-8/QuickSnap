# QuickSnap - macOS 原生轻量截图与离线 OCR 工具
Swift 5.10 + macOS 14.0+ + AppKit + SwiftUI + ScreenCaptureKit + Vision + Carbon + ServiceManagement

<directory>
docs/ - 持久化实施计划与功能进度清单（PLAN.md、CHECKLIST.md）
Sources/QuickSnapCore/ - 核心无界面业务逻辑层（配置、热键、标注模型与渲染、像素取色、自启服务、截屏、OCR、导出）
Sources/QuickSnap/ - 应用壳、Liquid Glass 设计系统、多屏截图遮罩画布与按需弹窗（App、Design、CaptureUI、Panels）
Resources/ - 应用 Bundle 元信息（Info.plist）与图标资源（AppIcon.icns）
Tests/QuickSnapTests/ - 核心算法、像素取色、图像导出与 Vision OCR 自动化测试
scripts/ - 图标生成、.app 组装签名与 .dmg 打包脚本
</directory>

<config>
Package.swift - SwiftPM 双 Target 工程定义与 macOS 14+ 平台配置
Resources/Info.plist - 应用 Bundle 配置（LSUIElement=true、权限声明、图标引用）
README.md - 项目功能说明、安装指南与源码构建方式
.gitignore - 忽略构建产物、系统缓存及证书私钥文件
docs/PLAN.md - 完整架构与阶段实施计划书
docs/CHECKLIST.md - 实时功能勾选清单（每完成一项立即打勾）
</config>

[PROTOCOL]: Update this header on change, then check GEMINI.md
