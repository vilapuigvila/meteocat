//
//  WeatherLoader.swift
//  meteocat
//
//  Created by albert vila on 17/6/25.
//

import Foundation
import SwiftUI

struct WeatherLoader: View {
    @State private var rotateSun = false
    @State private var pulseCloud = false
    @State private var dropOffset: CGFloat = -20
    @State private var showDrop = false

    var body: some View {
        ZStack {
            // Rotating sun
            SunShape()
                .stroke(Color.orange, lineWidth: 4)
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(rotateSun ? 360 : 0))
                .animation(Animation.linear(duration: 6).repeatForever(autoreverses: false), value: rotateSun)

            // Pulsing cloud
            CloudShape()
                .fill(Color.blue.opacity(0.4))
                .frame(width: 120, height: 80)
                .scaleEffect(pulseCloud ? 1.1 : 0.9)
                .opacity(pulseCloud ? 0.8 : 0.5)
                .animation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulseCloud)
                .offset(x: 0, y: 40)

            // Falling raindrop
            if showDrop {
                RaindropShape()
                    .fill(Color.blue)
                    .frame(width: 10, height: 20)
                    .offset(x: 0, y: dropOffset)
                    .animation(Animation.easeIn(duration: 0.8).delay(0.2).repeatForever(autoreverses: false), value: dropOffset)
            }
        }
        .onAppear {
            rotateSun = true
            pulseCloud = true
            showDrop = false
            dropOffset = 60
        }
    }
}

// MARK: - Shapes

struct SunShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.6
        // Draw center circle
        path.addEllipse(in: CGRect(x: center.x - radius,
                                   y: center.y - radius,
                                   width: radius * 2,
                                   height: radius * 2))
        // Draw rays
        for i in 0..<8 {
            let angle = Angle.degrees(Double(i) / 8 * 360)
            let start = CGPoint(x: center.x + cos(angle.radians) * radius,
                                y: center.y + sin(angle.radians) * radius)
            let end = CGPoint(x: center.x + cos(angle.radians) * radius * 1.4,
                              y: center.y + sin(angle.radians) * radius * 1.4)
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
    }
}

struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let height = rect.height * 0.6
        // Three circles for cloud
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY + height * 0.4,
                                   width: rect.width * 0.5, height: rect.height * 0.6))
        path.addEllipse(in: CGRect(x: rect.midX - rect.width * 0.25, y: rect.minY,
                                   width: rect.width * 0.6, height: rect.height * 0.7))
        path.addEllipse(in: CGRect(x: rect.maxX - rect.width * 0.5, y: rect.minY + height * 0.4,
                                   width: rect.width * 0.5, height: rect.height * 0.6))
        // Bottom rectangle
        path.addRect(CGRect(x: rect.minX + rect.width * 0.1,
                            y: rect.minY + height,
                            width: rect.width * 0.8,
                            height: rect.height * 0.4))
        return path
    }
}

struct RaindropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: Angle(degrees: 180),
                    endAngle: Angle(degrees: 0),
                    clockwise: false)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct WeatherLoader_Previews: PreviewProvider {
    static var previews: some View {
        WeatherLoader()
            .frame(width: 200, height: 200)
            .padding()
    }
}
