import SwiftUI

#if os(iOS)
import UIKit

@MainActor
final class AppPreviewPrivacyManager {
    static let shared = AppPreviewPrivacyManager()

    private let overlayTag = 0x507658

    private init() {}

    func updateProtection(isEnabled: Bool, scenePhase: ScenePhase) {
        let shouldProtect = isEnabled && scenePhase != .active

        for window in appWindows {
            if shouldProtect {
                if !window.isHidden && window.windowLevel == .normal {
                    installOverlay(on: window)
                }
            } else {
                removeOverlay(from: window)
            }
        }
    }

    func removeAllOverlays() {
        for window in appWindows {
            removeOverlay(from: window)
        }
    }

    private var appWindows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    private func installOverlay(on window: UIWindow) {
        if let overlay = window.viewWithTag(overlayTag) {
            window.bringSubviewToFront(overlay)
            return
        }

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        blurView.tag = overlayTag
        blurView.frame = window.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.isUserInteractionEnabled = false

        let tintView = UIView(frame: blurView.bounds)
        tintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.18)
        blurView.contentView.addSubview(tintView)

        window.addSubview(blurView)
        window.bringSubviewToFront(blurView)
    }

    private func removeOverlay(from window: UIWindow) {
        window.viewWithTag(overlayTag)?.removeFromSuperview()
    }
}
#else
@MainActor
final class AppPreviewPrivacyManager {
    static let shared = AppPreviewPrivacyManager()

    private init() {}

    func updateProtection(isEnabled: Bool, scenePhase: ScenePhase) {}

    func removeAllOverlays() {}
}
#endif
