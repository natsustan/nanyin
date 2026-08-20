//
//  DebugLog.swift
//  Nanyin
//

import Foundation

/// Unbuffered debug logging to stderr (survives process kill, unlike print).
/// Lives in its own file so SpotifyClient compiles standalone in the
/// state-reducer test binary (agent_check.sh).
func dlog(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write(Data("[nanyin] \(message())\n".utf8))
}
