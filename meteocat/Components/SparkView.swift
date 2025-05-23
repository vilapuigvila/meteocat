//
//  SparkView.swift
//  meteocat
//
//  Created by albert vila on 19/5/25.
//

import SwiftUI

struct SparkView: UIViewRepresentable {
    
    let isAddinng: Bool
    
    func makeSparkImage(symbol: String, color: UIColor) -> CGImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let image = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal)

        // Render to image context to preserve color
        let size = CGSize(width: 20, height: 20)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        image?.draw(in: CGRect(origin: .zero, size: size))
        let renderedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return renderedImage?.cgImage
    }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: 12, y: 12) // Center for 24x24 heart icon
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 10, height: 10)

        let colors: [UIColor] = {
            if isAddinng {
                return [.systemRed, .systemYellow, .systemBlue]
            } else {
                return [UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.75)]
            }
        }()

        let cells: [CAEmitterCell] = colors.compactMap { color in
            guard let cgImage = makeSparkImage(symbol: "sparkle", color: color) else { return nil }
            let cell = CAEmitterCell()
            cell.contents = cgImage
            cell.birthRate = 30
            cell.lifetime = 0.4
            cell.velocity = 100
            cell.velocityRange = 50
            cell.scale = 0.05
            cell.scaleRange = 0.02
            cell.emissionRange = .pi * 2
            return cell
        }

        emitter.emitterCells = cells

        emitter.emitterCells = cells
        emitter.beginTime = CACurrentMediaTime()
        emitter.birthRate = 0 // Start off

        view.layer.addSublayer(emitter)

        // Trigger the sparks just after creation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            emitter.birthRate = 100
        }

        // Stop emitting after a short burst
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            emitter.birthRate = 0
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
