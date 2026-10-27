import SwiftUI
import UIKit

enum HingePose: Equatable {
    case unavailable, closed, partiallyOpen, fullyOpen
}

final class GlassViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let glassView = GlassView()

    override func loadView() {
        view = glassView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                guard let hinge = update.hinge else {
                    self.glassView.hingeChanged(angle: nil, pose: .unavailable)
                    return
                }
                let pose: HingePose
                switch hinge.status {
                case .closed: pose = .closed
                case .partiallyOpen: pose = .partiallyOpen
                case .fullyOpen: pose = .fullyOpen
                default: pose = .unavailable
                }
                self.glassView.hingeChanged(angle: hinge.angle, pose: pose)
            }
            view.addInteraction(interaction)
        }

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(showOptions(_:)))
        hold.numberOfTouchesRequired = 2
        hold.minimumPressDuration = 0.7
        view.addGestureRecognizer(hold)
    }

    @objc private func showOptions(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        presentOptions()
    }

    private func presentOptions() {
        guard presentedViewController == nil else { return }
        let size = glassView.bounds.size
        guard size.width > 0 else { return }
        var previews: [PrankScreen: UIImage] = [:]
        for screen in PrankScreen.allCases {
            previews[screen] = ScreenArt.render(screen, size: size, scale: 0.4, palette: GlassPalette.all[1], date: Date())
        }
        let options = OptionsView(previews: previews, previewAspect: size.width / size.height) { [weak self] in
            self?.dismiss(animated: true) { self?.glassView.applySettings() }
        }
        let host = UIHostingController(rootView: options)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        host.presentationController?.delegate = self
        Haptics.shared.crack(intensity: 0.5)
        present(host, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        glassView.applySettings()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ShowOptions") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.presentOptions() }
        }
        #endif
    }

    override var canBecomeFirstResponder: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { glassView.smashCenter() }
    }
}
