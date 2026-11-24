/**
 * [INPUT]: 依赖 Foundation、ServiceManagement（SMAppService）
 * [OUTPUT]: 提供 LaunchAtLoginService（macOS 14+ 登录项开机自启动状态读取与切换）
 * [POS]: QuickSnapCore 的系统集成服务，供偏好设置面板控制开机自启动
 * [PROTOCOL]: Update this header on change, then check GEMINI.md
 */

import Foundation
import ServiceManagement

public enum LaunchAtLoginService {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
