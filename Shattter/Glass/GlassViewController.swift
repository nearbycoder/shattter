import UIKit

enum HingePose: Equatable {
    case unavailable, closed, partiallyOpen, fullyOpen
}

final class GlassViewController: UIViewController {
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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { glassView.smashCenter() }
    }
}
