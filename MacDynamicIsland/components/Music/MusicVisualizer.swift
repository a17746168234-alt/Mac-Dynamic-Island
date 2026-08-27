//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import AppKit
import Cocoa
import SwiftUI

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var isPlaying: Bool = true

    private let animationValues: [[CGFloat]] = [
        [0.34, 0.92, 0.48, 0.78, 0.34],
        [0.56, 0.38, 1.00, 0.62, 0.56],
        [0.42, 0.82, 0.36, 0.94, 0.42],
        [0.70, 0.40, 0.86, 0.32, 0.70]
    ]
    private let animationDurations: [CFTimeInterval] = [0.92, 1.08, 0.84, 1.16]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let barWidth: CGFloat = 2
        let barCount = 4
        let spacing: CGFloat = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        let totalHeight: CGFloat = 14
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            let path = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                                    xRadius: barWidth / 2,
                                    yRadius: barWidth / 2)
            barLayer.path = path.cgPath
            barLayers.append(barLayer)
            layer?.addSublayer(barLayer)
        }
        resetBars()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeAnimations(reset: false)
        } else if isPlaying {
            startAnimating()
        }
    }

    private func startAnimating() {
        guard isPlaying, window != nil else { return }

        let startTime = CACurrentMediaTime()
        for (index, barLayer) in barLayers.enumerated() {
            guard barLayer.animation(forKey: "spectrumScale") == nil else { continue }

            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = animationValues[index]
            animation.keyTimes = [0, 0.24, 0.51, 0.76, 1]
            animation.duration = animationDurations[index]
            animation.beginTime = startTime - Double(index) * 0.11
            animation.repeatCount = .infinity
            animation.calculationMode = .cubic
            animation.timingFunctions = Array(
                repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                count: animationValues[index].count - 1
            )
            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(
                    minimum: 30,
                    maximum: 120,
                    preferred: 60
                )
            }
            barLayer.add(animation, forKey: "spectrumScale")
        }
    }

    private func stopAnimating() {
        removeAnimations(reset: true)
    }

    private func resetBars() {
        for barLayer in barLayers {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
        }
    }

    private func removeAnimations(reset: Bool) {
        for barLayer in barLayers {
            barLayer.removeAnimation(forKey: "spectrumScale")
        }
        if reset {
            resetBars()
        }
    }

    func setPlaying(_ playing: Bool) {
        guard isPlaying != playing || (playing && barLayers.first?.animation(forKey: "spectrumScale") == nil)
        else { return }
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    func prepareForRemoval() {
        isPlaying = false
        removeAnimations(reset: false)
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    let isPlaying: Bool
    
    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }
    
    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }

    static func dismantleNSView(_ nsView: AudioSpectrum, coordinator: ()) {
        nsView.prepareForRemoval()
    }
}

#Preview {
    AudioSpectrumView(isPlaying: true)
        .frame(width: 16, height: 20)
        .padding()
}
