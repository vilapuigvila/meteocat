//
//  HeadingLocationView.swift
//  meteocat
//

import MapKit
import UIKit

/// The user's place on the map: an orange square with a wedge toward where the phone points and its compass point
/// (`NW 315°`) beside it. Without a compass (a simulator, or a phone that lost it) only the square shows.
final class HeadingLocationView: MKAnnotationView {

    static let reuseIdentifier = "userLocationWithHeading"

    private static let side: CGFloat = 112
    private static let wedgeRadius: CGFloat = 52

    private let wedge = CAShapeLayer()
    private let square = UIView()
    private let label = UILabel()

    /// Degrees clockwise from north, or `nil` when unknown.
    var heading: Double? {
        didSet { showHeading() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        canShowCallout = false
        isEnabled = false
        displayPriority = .required
        zPriority = .max

        let center = CGPoint(x: Self.side / 2, y: Self.side / 2)
        wedge.frame = bounds
        let half = 28 * CGFloat.pi / 180
        let path = UIBezierPath()
        path.move(to: center)
        path.addArc(withCenter: center, radius: Self.wedgeRadius, startAngle: -.pi / 2 - half, endAngle: -.pi / 2 + half, clockwise: true)
        path.close()
        wedge.path = path.cgPath
        layer.addSublayer(wedge)

        square.frame = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
        square.layer.borderWidth = 2
        addSubview(square)

        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textAlignment = .center
        label.layer.borderWidth = 1
        addSubview(label)

        applyColors()
        showHeading()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: HeadingLocationView, _) in
            view.applyColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyColors() {
        let orange = UIColor(Signal.orange)
        let ink = UIColor(Signal.ink)
        let paper = UIColor(Signal.paper)
        traitCollection.performAsCurrent {
            wedge.fillColor = orange.withAlphaComponent(0.4).cgColor
            square.backgroundColor = orange
            square.layer.borderColor = ink.cgColor
            label.textColor = ink
            label.backgroundColor = paper
            label.layer.borderColor = ink.cgColor
        }
    }

    private func showHeading() {
        guard let heading else {
            wedge.isHidden = true
            label.isHidden = true
            return
        }
        wedge.isHidden = false
        label.isHidden = false
        // the wedge is drawn pointing north; the map keeps north up
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wedge.setAffineTransform(CGAffineTransform(rotationAngle: heading * .pi / 180))
        CATransaction.commit()

        label.text = Compass.text(for: heading)
        label.sizeToFit()
        let size = CGSize(width: label.bounds.width + 12, height: label.bounds.height + 4)
        label.frame = CGRect(x: (Self.side - size.width) / 2, y: Self.side / 2 + 14, width: size.width, height: size.height)
    }
}
