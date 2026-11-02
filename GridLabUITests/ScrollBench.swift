// Measures real iOS scroll physics on a TikTok-like grid with automated swipes:
//  1. how far one flick travels at different speeds (already-loaded grid)
//  2. whether quick repeated flicks build up speed (momentum stacking)
//  3. how fast a grid that loads page by page can be crossed, by flick spacing
//  4. how often a fast swipe is read as a tap
import XCTest
import ObjectiveC

final class ScrollBench: XCTestCase {
    override class func setUp() {
        super.setUp()
        // XCUITest normally waits for the app to be idle (scrolling stopped) before each gesture.
        // Turning that off lets us swipe on our own schedule, like Switch Control does.
        guard let cls = NSClassFromString("XCUIApplicationProcess") else { print("BENCH noswizzle"); return }
        for name in ["waitForQuiescenceIncludingAnimationsIdle:", "waitForQuiescenceIncludingAnimationsIdle:isPreEvent:"] {
            let sel = NSSelectorFromString(name)
            guard let m = class_getInstanceMethod(cls, sel) else { continue }
            if name.hasSuffix("isPreEvent:") {
                let block: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
                method_setImplementation(m, imp_implementationWithBlock(block))
            } else {
                let block: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
                method_setImplementation(m, imp_implementationWithBlock(block))
            }
            print("BENCH swizzled \(name)")
        }
    }

    func launch(_ env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = env
        app.launch()
        Thread.sleep(forTimeInterval: 2)
        return app
    }
    func state(_ app: XCUIApplication) -> [String: Double] {
        let s = app.staticTexts["status"].label
        return ((try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Double]) ?? [:]
    }
    func settle(_ app: XCUIApplication, max: Double = 8) -> [String: Double] {
        let end = Date().addingTimeInterval(max)
        var st = state(app)
        while Date() < end && (st["moving"] ?? 0) == 1 { Thread.sleep(forTimeInterval: 0.3); st = state(app) }
        Thread.sleep(forTimeInterval: 0.3)
        return state(app)
    }
    func flick(_ app: XCUIApplication, velocity: CGFloat, length: CGFloat = 0.45) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78 - length))
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: XCUIGestureVelocity(velocity), thenHoldForDuration: 0)
    }
    func emit(_ name: String, _ d: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])
        print("BENCH \(name) \(String(data: data, encoding: .utf8)!)")
    }

    // 1. One flick, already-loaded grid
    func test1_singleFlick() {
        for v in [1500, 3000, 5000, 8000] as [CGFloat] {
            let app = launch(["PRELOAD": "30000"])
            let a = settle(app)
            let t = Date(); flick(app, velocity: v); let call = Date().timeIntervalSince(t)
            let b = settle(app)
            emit("single", ["v": v, "rows": (b["row"] ?? 0) - (a["row"] ?? 0), "maxV": b["maxV"] ?? 0, "callSec": call, "opened": b["opened"] ?? 0, "rowH": b["rowH"] ?? 0])
            app.terminate()
        }
    }

    // 2. Ten quick flicks: does speed build up?
    func test2_repeatedFlicks() {
        for interval in [0.0, 0.3, 0.6, 1.0] {
            let app = launch(["PRELOAD": "36000"])
            let a = settle(app)
            let t0 = Date()
            for i in 0..<10 {
                flick(app, velocity: 5000)
                let target = t0.addingTimeInterval(Double(i + 1) * interval)
                let wait = target.timeIntervalSinceNow
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            }
            let burst = Date().timeIntervalSince(t0)
            let b = settle(app, max: 15)
            emit("repeat", ["interval": interval, "burstSec": burst, "rows": (b["row"] ?? 0) - (a["row"] ?? 0), "maxV": b["maxV"] ?? 0, "opened": b["opened"] ?? 0])
            app.terminate()
        }
    }

    // 3. Grid that loads page by page: progress in 30 s by flick spacing and network delay
    func test3_coldThroughput() {
        let runs: [(Double, Double)] = [(0.6, 0.0), (0.6, 0.3), (0.6, 0.6), (0.6, 1.0), (0.6, 1.6), (1.2, 0.3), (1.2, 1.0), (1.2, 1.6)]
        for (latency, interval) in runs {
            let app = launch(["PRELOAD": "0", "LATENCY": "\(latency)", "PAGE": "18", "PREFETCH_ROWS": "6"])
            let t0 = Date(); var flicks = 0
            while Date().timeIntervalSince(t0) < 30 {
                flick(app, velocity: 5000); flicks += 1
                let target = t0.addingTimeInterval(Double(flicks) * interval)
                let wait = target.timeIntervalSinceNow
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            }
            let b = settle(app)
            emit("cold", ["latency": latency, "interval": interval, "flicks": flicks, "sec": Date().timeIntervalSince(t0), "loaded": b["loaded"] ?? 0, "rows": b["row"] ?? 0, "opened": b["opened"] ?? 0])
            app.terminate()
        }
    }

    // 4. Short, fast swipes: how often is one read as a tap?
    func test4_tapRisk() {
        let app = launch(["PRELOAD": "36000"])
        for (length, v) in [(0.05, 3000), (0.1, 3000), (0.2, 5000), (0.45, 5000)] as [(CGFloat, CGFloat)] {
            let a = state(app)["opened"] ?? 0
            for _ in 0..<20 { flick(app, velocity: v, length: length); Thread.sleep(forTimeInterval: 0.3) }
            let b = settle(app)
            emit("tap", ["length": length, "v": v, "swipes": 20, "opened": (b["opened"] ?? 0) - a])
        }
    }
}
