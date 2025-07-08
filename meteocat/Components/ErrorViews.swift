//
//  ErrorViews.swift
//  meteocat
//
//  Created by albert vila on 23/6/25.
//

import SwiftUI

struct MissingStationErrorView: View {
    @State private var shake = true
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.orange)
                .rotationEffect(.degrees(shake ? 5 : -5), anchor: .center)
                .animation(
                    Animation.easeInOut(duration: 0.15)
                        .repeatCount(5, autoreverses: true)
                , value: shake)
                .onAppear { shake.toggle() }

            Text("Please select a station from the list.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(radius: 4)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// A view that shows a fancy image when a network failure occurs.
struct NetworkFailureErrorView: View {
    @State private var pulse = true
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.red)
                .scaleEffect(pulse ? 1.1 : 0.9)
                .opacity(pulse ? 0.8 : 1)
                .animation(
                    Animation
                        .easeInOut(duration: 0.5)
                        .repeatCount(5, autoreverses: true), value: pulse
                )
                .onAppear {
                    pulse.toggle()
                }

            Text("Network Error. Please try again.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(radius: 4)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Preview
/*
struct ErrorViews_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MissingStationErrorView()
                .previewLayout(.sizeThatFits)
                .padding()

            NetworkFailureErrorView()
                .previewLayout(.sizeThatFits)
                .padding()
        }
    }
}*/
