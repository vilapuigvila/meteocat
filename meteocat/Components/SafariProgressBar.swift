//
//  SafariProgressBar.swift
//  meteocat
//
//  Created by albert vila on 5/2/25.
//

import SwiftUI

struct SafariProgressBar: View {
    @State private var progress: CGFloat = 0.0
    @Binding var isLoading: Bool
    
    var body: some View {
        if !isLoading {
            withAnimation {
                EmptyView().frame(height: 4)
            }
        } else {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .frame(height: 4)
                        .foregroundColor(Color.gray.opacity(0.3))
                    
                    Rectangle()
                        .frame(width: progress, height: 4)
                        .foregroundColor(.gray)
                        .opacity(progress == 0 ? 0 : 1)
                        .animation(.linear(duration: animationTimeInterval), value: progress)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    startLoading(parentWitdh: geometry.size.width)
                }
            }
        }
    }
    private let animationTimeInterval: TimeInterval = 0.2
    func startLoading(parentWitdh: CGFloat) {
        progress = 0
        
        // Simulate a loading sequence
        Timer.scheduledTimer(withTimeInterval: animationTimeInterval, repeats: true) { timer in
            let increment = parentWitdh * 0.05
            if progress < parentWitdh * 0.98 {
                progress += increment
            } else {
                progress = 0
            }
            if !isLoading {
                timer.invalidate()
            }
        }
    }
    
    func finishLoading() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                progress = UIScreen.main.bounds.width
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    progress = 0
                    isLoading = false
                }
            }
        }
    }
}
