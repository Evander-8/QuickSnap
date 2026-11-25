import XCTest
@testable import QuickSnapCore

final class SelectionAndHistoryTests: XCTestCase {
    func testNormalizedRectHandlesReverseDrag() {
        let rect = SelectionMath.normalizedRect(
            from: CGPoint(x: 300, y: 240),
            to: CGPoint(x: 100, y: 40)
        )
        XCTAssertEqual(rect, CGRect(x: 100, y: 40, width: 200, height: 200))
    }

    func testMovedRectClampsInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = CGRect(x: 900, y: 700, width: 80, height: 80)
        let moved = SelectionMath.movedRect(rect, delta: CGSize(width: 100, height: 100), within: bounds)
        XCTAssertEqual(moved, CGRect(x: 920, y: 720, width: 80, height: 80))

        let movedNegative = SelectionMath.movedRect(rect, delta: CGSize(width: -1200, height: -900), within: bounds)
        XCTAssertEqual(movedNegative, CGRect(x: 0, y: 0, width: 80, height: 80))
    }

    func testResizedRectEnforcesMinimumSizeAndBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)

        let shrunk = SelectionMath.resizedRect(
            rect,
            handle: .topLeft,
            to: CGPoint(x: 250, y: 250),
            within: bounds,
            minSize: 12
        )
        XCTAssertEqual(shrunk.width, 12)
        XCTAssertEqual(shrunk.height, 12)
        XCTAssertEqual(shrunk.maxX, 200)
        XCTAssertEqual(shrunk.maxY, 200)

        let expanded = SelectionMath.resizedRect(
            rect,
            handle: .bottomRight,
            to: CGPoint(x: 650, y: 700),
            within: bounds,
            minSize: 12
        )
        XCTAssertEqual(expanded, CGRect(x: 100, y: 100, width: 400, height: 400))
    }

    func testHitTestHandleDetectsCornersAndEdges() {
        let rect = CGRect(x: 50, y: 60, width: 200, height: 100)
        XCTAssertEqual(SelectionMath.hitTestHandle(CGPoint(x: 52, y: 62), rect: rect), .topLeft)
        XCTAssertEqual(SelectionMath.hitTestHandle(CGPoint(x: 250, y: 110), rect: rect), .right)
        XCTAssertNil(SelectionMath.hitTestHandle(CGPoint(x: 150, y: 110), rect: rect))
    }

    func testAnnotationHistoryUndoRedoAndBranchClear() {
        var history = AnnotationHistory()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)

        let item1 = AnnotationItem(tool: .rectangle, color: .red, strokeWidth: 4)
        let item2 = AnnotationItem(tool: .arrow, color: .blue, strokeWidth: 4)
        let item3 = AnnotationItem(tool: .ellipse, color: .green, strokeWidth: 4)

        history.append(item1)
        history.append(item2)
        XCTAssertEqual(history.items.count, 2)
        XCTAssertTrue(history.canUndo)

        let undone = history.undo()
        XCTAssertEqual(undone?.id, item2.id)
        XCTAssertEqual(history.items.count, 1)
        XCTAssertTrue(history.canRedo)

        let redone = history.redo()
        XCTAssertEqual(redone?.id, item2.id)
        XCTAssertEqual(history.items.count, 2)
        XCTAssertFalse(history.canRedo)

        history.undo()
        history.append(item3)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.items.map(\.id), [item1.id, item3.id])
    }

    func testSettingsStorePersistenceAndReset() {
        let suiteName = "com.quicksnap.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.exportFormat = .jpeg
        store.jpegQuality = 0.8
        store.filenameTemplate = "Snap_{yyyy}-{MM}-{dd}_{W}x{H}"
        store.playSound = false
        store.regionHotkey = HotkeyCombo(keyCode: 11, modifiers: 256)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.exportFormat, .jpeg)
        XCTAssertEqual(reloaded.jpegQuality, 0.8, accuracy: 0.001)
        XCTAssertEqual(reloaded.filenameTemplate, "Snap_{yyyy}-{MM}-{dd}_{W}x{H}")
        XCTAssertFalse(reloaded.playSound)
        XCTAssertEqual(reloaded.regionHotkey, HotkeyCombo(keyCode: 11, modifiers: 256))

        reloaded.resetToDefaults()
        XCTAssertEqual(reloaded.exportFormat, .png)
        XCTAssertEqual(reloaded.filenameTemplate, SettingsStore.defaultFilenameTemplate)
        XCTAssertTrue(reloaded.playSound)
        XCTAssertEqual(reloaded.regionHotkey, .defaultRegionCapture)
    }

    func testFilenameFormatterReplacesTokensAndSanitizesIllegalChars() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 24
        comps.hour = 9
        comps.minute = 5
        comps.second = 3
        let fixedDate = Calendar.current.date(from: comps)!

        let formatted = FilenameFormatter.makeFilename(
            template: "Shot_{yyyy}-{MM}-{dd}_{HH}{mm}{ss}_{W}x{H}",
            format: .png,
            date: fixedDate,
            pixelSize: (1920, 1080)
        )
        XCTAssertEqual(formatted, "Shot_2026-11-24_090503_1920x1080.png")

        // 非法路径字符和多余后缀应被清洗
        let sanitized = FilenameFormatter.makeFilename(
            template: "..my/bad:name.png",
            format: .jpeg,
            date: fixedDate
        )
        XCTAssertEqual(sanitized, "my_bad_name.jpg")

        // 空模板自动回退默认时间戳
        let fallback = FilenameFormatter.makeFilename(
            template: "   ...   ",
            format: .png,
            date: fixedDate
        )
        XCTAssertEqual(fallback, "Screenshot_20261124_090503.png")
    }

    func testAppKitGlobalFrameConvertsFlippedSelectionOnPrimaryAndSecondaryScreens() {
        let primaryScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let primarySelection = CGRect(x: 100, y: 50, width: 320, height: 200)
        let primaryGlobal = SelectionMath.appKitGlobalFrame(for: primarySelection, in: primaryScreen)
        XCTAssertEqual(primaryGlobal, CGRect(x: 100, y: 650, width: 320, height: 200))

        let secondaryScreen = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
        let secondarySelection = CGRect(x: 40, y: 80, width: 400, height: 300)
        let secondaryGlobal = SelectionMath.appKitGlobalFrame(for: secondarySelection, in: secondaryScreen)
        XCTAssertEqual(secondaryGlobal, CGRect(x: 1480, y: 520, width: 400, height: 300))
    }

    func testQuartzRectToDisplayLocalAcrossMultiMonitorLayout() {
        let primaryHeight: CGFloat = 900
        let primaryFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let topMonitorFrame = CGRect(x: 0, y: 900, width: 1920, height: 1080)

        let winOnPrimary = SelectionMath.quartzRectToDisplayLocal(
            CGRect(x: 120, y: 80, width: 600, height: 400),
            displayScreenFrame: primaryFrame,
            primaryScreenHeight: primaryHeight
        )
        XCTAssertEqual(winOnPrimary, CGRect(x: 120, y: 80, width: 600, height: 400))

        // 位于主屏上方副屏的窗口在 Quartz 坐标系下 y 为负值
        let winOnTopMonitor = SelectionMath.quartzRectToDisplayLocal(
            CGRect(x: 50, y: -980, width: 500, height: 300),
            displayScreenFrame: topMonitorFrame,
            primaryScreenHeight: primaryHeight
        )
        XCTAssertEqual(winOnTopMonitor, CGRect(x: 50, y: 100, width: 500, height: 300))

        // 过小窗口（< 40pt）会被过滤
        let tiny = SelectionMath.quartzRectToDisplayLocal(
            CGRect(x: 10, y: 10, width: 24, height: 24),
            displayScreenFrame: primaryFrame,
            primaryScreenHeight: primaryHeight
        )
        XCTAssertNil(tiny)
    }

    func testAnnotationHistoryNextStepNumberTracksUndoRedo() {
        var history = AnnotationHistory()
        XCTAssertEqual(history.nextStepNumber, 1)

        history.append(AnnotationItem(tool: .stepNumber, color: .red, strokeWidth: 4, stepNumber: 1))
        XCTAssertEqual(history.nextStepNumber, 2)

        history.append(AnnotationItem(tool: .brush, color: .blue, strokeWidth: 4))
        XCTAssertEqual(history.nextStepNumber, 2)

        history.append(AnnotationItem(tool: .stepNumber, color: .red, strokeWidth: 4, stepNumber: 2))
        XCTAssertEqual(history.nextStepNumber, 3)

        history.undo()
        XCTAssertEqual(history.nextStepNumber, 2)

        history.redo()
        XCTAssertEqual(history.nextStepNumber, 3)
    }

    func testAsyncTimeoutResolvesFastAndRejectsHungOperation() async throws {
        let fastResult = try await AsyncTimeout.run(
            seconds: 1.0,
            timeoutError: ScreenCaptureError.timedOut
        ) {
            return 42
        }
        XCTAssertEqual(fastResult, 42)

        do {
            let _: Int = try await AsyncTimeout.run(
                seconds: 0.12,
                timeoutError: ScreenCaptureError.timedOut
            ) {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return 99
            }
            XCTFail("Expected ScreenCaptureError.timedOut")
        } catch let error as ScreenCaptureError {
            XCTAssertEqual(error, .timedOut)
        }
    }
}
