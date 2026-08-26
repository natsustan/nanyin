import Foundation

@main
private enum ThemePreferenceTests {
    static func main() {
        testFreshPreferenceUsesNanyinDark()
        testPreferenceRoundTrip()
        testUnknownPreferenceFallsBackWithoutRewriting()
        testThemeFillsPreserveSolidAndGradientSemantics()
        print("Theme preference tests passed")
    }

    private static func testFreshPreferenceUsesNanyinDark() {
        withDefaults { defaults in
            expect(
                AppThemeID(storedValue: defaults.string(forKey: AppThemeID.preferenceKey))
                    == .nanyinDark,
                "a fresh preference must resolve to Nanyin Dark"
            )
        }
    }

    private static func testPreferenceRoundTrip() {
        withDefaults { defaults in
            defaults.set(AppThemeID.classic2010.rawValue, forKey: AppThemeID.preferenceKey)
            expect(
                AppThemeID(storedValue: defaults.string(forKey: AppThemeID.preferenceKey))
                    == .classic2010,
                "a stored theme must round-trip"
            )
        }
    }

    private static func testUnknownPreferenceFallsBackWithoutRewriting() {
        withDefaults { defaults in
            defaults.set("removed-theme", forKey: AppThemeID.preferenceKey)
            expect(
                AppThemeID(storedValue: defaults.string(forKey: AppThemeID.preferenceKey))
                    == .nanyinDark,
                "an unknown preference must resolve to Nanyin Dark"
            )
            expect(
                defaults.string(forKey: AppThemeID.preferenceKey) == "removed-theme",
                "resolving an unknown preference must not rewrite stored preferences"
            )
        }
    }

    private static func testThemeFillsPreserveSolidAndGradientSemantics() {
        expect(
            AppTheme.nanyinDark.colors.contentBackground.isSolid,
            "Nanyin Dark background should remain a solid token"
        )
        expect(
            !AppTheme.classic2010.colors.contentBackground.isSolid,
            "Classic 2010 background should remain a gradient token"
        )
        expect(
            AppTheme.classic2010.colors.rowAlternate.isSolid,
            "Classic 2010 zebra rows should use a solid alternate band token"
        )
        expect(
            AppTheme.nanyinDark.colors.rowAlternate.isSolid,
            "Nanyin Dark should retain a clear alternate row token"
        )
    }

    private static func withDefaults(_ operation: (UserDefaults) -> Void) {
        let suite = "ThemePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        operation(defaults)
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
            exit(1)
        }
    }
}
