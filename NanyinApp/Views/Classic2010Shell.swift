//
//  Classic2010Shell.swift
//  Nanyin
//

/// Classic's shell adapter is a stable presentation marker. The common shell
/// scaffold consumes it without replacing the shared content owner.
enum Classic2010Shell: ShellAdapter {
    static let kind = ShellPresentationKind.classic2010
}
