import SwiftUI
import WebKit

final class GameView: UIViewController {
    let url = URL(string: "https://407notfound.github.io/s2cf/")!
    var web: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        web = WKWebView(frame: view.bounds, configuration: cfg)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.isOpaque = false
        web.backgroundColor = .black
        view.addSubview(web)
        web.load(URLRequest(url: url))
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
}

struct GameHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GameView { GameView() }
    func updateUIViewController(_ vc: GameView, context: Context) {}
}

@main
struct S2CFApp: App {
    var body: some Scene {
        WindowGroup {
            GameHost().ignoresSafeArea()
        }
    }
}
