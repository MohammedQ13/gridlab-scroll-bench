// GridLab: a stand-in for a TikTok-style Saved grid (3 columns, 3:4 tiles, pages loaded on demand
// with network-like delay). Used to measure real iOS scrolling physics under automated swipes.
import UIKit

struct Config {
    let latency: Double, jitter: Double, page: Int, prefetchRows: Int, total: Int, preload: Int
    static func fromEnv() -> Config {
        let e = ProcessInfo.processInfo.environment
        func d(_ k: String, _ v: Double) -> Double { Double(e[k] ?? "") ?? v }
        return Config(latency: d("LATENCY", 0.6), jitter: d("JITTER", 0.3), page: Int(d("PAGE", 18)),
                      prefetchRows: Int(d("PREFETCH_ROWS", 6)), total: Int(d("TOTAL", 36000)), preload: Int(d("PRELOAD", 0)))
    }
}

final class Cell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor(white: 0.25, alpha: 1)
        label.textColor = .white; label.font = .systemFont(ofSize: 10)
        label.frame = contentView.bounds.insetBy(dx: 4, dy: 4)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class GridVC: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    let cfg = Config.fromEnv()
    var loaded = 0, loading = false, pages = 0, opened = 0
    var cv: UICollectionView!
    let status = UILabel()
    var link: CADisplayLink?
    var frameCount = 0
    var lastY: CGFloat = 0, lastT: CFTimeInterval = 0, maxV: CGFloat = 0
    let t0 = CACurrentMediaTime()

    var itemW: CGFloat { (view.bounds.width - 2) / 3 }
    var rowH: CGFloat { itemW * 4 / 3 + 1 }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 1; layout.minimumLineSpacing = 1
        cv = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cv.backgroundColor = .black
        cv.dataSource = self; cv.delegate = self
        cv.register(Cell.self, forCellWithReuseIdentifier: "c")
        cv.accessibilityIdentifier = "grid"
        view.addSubview(cv)
        status.accessibilityIdentifier = "status"
        status.font = .systemFont(ofSize: 6); status.numberOfLines = 1; status.alpha = 0.1
        status.frame = CGRect(x: 0, y: 60, width: 320, height: 8)
        view.addSubview(status)
        loaded = min(cfg.preload > 0 ? cfg.preload : cfg.page, cfg.total)
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    func collectionView(_ c: UICollectionView, numberOfItemsInSection s: Int) -> Int { loaded }
    func collectionView(_ c: UICollectionView, cellForItemAt i: IndexPath) -> UICollectionViewCell {
        let cell = c.dequeueReusableCell(withReuseIdentifier: "c", for: i) as! Cell
        cell.label.text = "\(i.item)"
        return cell
    }
    func collectionView(_ c: UICollectionView, layout l: UICollectionViewLayout, sizeForItemAt i: IndexPath) -> CGSize {
        CGSize(width: floor(itemW), height: floor(itemW * 4 / 3))
    }
    // A tap opens a "video" in TikTok; here we only count it (an accidental tap during a dive).
    func collectionView(_ c: UICollectionView, didSelectItemAt i: IndexPath) { opened += 1 }
    func scrollViewDidScroll(_ s: UIScrollView) { maybeLoad() }

    func gaussian() -> Double {
        let u = max(Double.random(in: 0..<1), 1e-9), v = Double.random(in: 0..<1)
        return sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }

    func maybeLoad() {
        guard !loading, loaded < cfg.total else { return }
        let remainingRows = (cv.contentSize.height - (cv.contentOffset.y + cv.bounds.height)) / rowH
        guard remainingRows < CGFloat(cfg.prefetchRows) else { return }
        loading = true
        let delay = cfg.latency * exp(cfg.jitter * gaussian())
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            let n = min(cfg.page, cfg.total - loaded)
            let paths = (loaded..<(loaded + n)).map { IndexPath(item: $0, section: 0) }
            loaded += n; pages += 1
            cv.performBatchUpdates({ cv.insertItems(at: paths) }) { _ in self.loading = false; self.maybeLoad() }
        }
    }

    @objc func tick() {
        let now = CACurrentMediaTime(), y = cv.contentOffset.y
        if lastT > 0 { maxV = max(maxV, abs(y - lastY) / CGFloat(now - lastT)) }
        lastY = y; lastT = now
        frameCount += 1
        if frameCount % 6 == 0 {
            let rows = y / rowH
            status.text = String(format: "{\"t\":%.3f,\"row\":%.2f,\"loaded\":%d,\"pages\":%d,\"opened\":%d,\"maxV\":%.0f,\"rowH\":%.1f,\"moving\":%d}",
                                 now - t0, rows, loaded, pages, opened, maxV, rowH, (cv.isDecelerating || cv.isDragging) ? 1 : 0)
        }
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ app: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = GridVC()
        window?.makeKeyAndVisible()
        return true
    }
}
