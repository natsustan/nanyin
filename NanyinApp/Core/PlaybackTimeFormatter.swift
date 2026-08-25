//
//  PlaybackTimeFormatter.swift
//  Nanyin
//

import Foundation

enum PlaybackTimeFormatter {
    static func string(fromMilliseconds milliseconds: UInt32) -> String {
        let seconds = Int(milliseconds) / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
