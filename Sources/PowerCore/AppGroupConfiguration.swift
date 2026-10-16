import Foundation

/// App Group build-time configuration shared by the host app and the widget
/// extension. (Named AppGroupConfiguration to avoid colliding with
/// WidgetKit's WidgetConfiguration type.)
///
/// The App Group identifier MUST be prefixed with the signing team's
/// Team ID: sandboxed widget extensions can only access team-ID-prefixed
/// group containers (containermanagerd rejects unprefixed groups).
///
/// The Team ID is NOT hardcoded in source — every contributor has a different
/// one. `scripts/build_app.sh` reads it from `TeamID.local` (gitignored) and
/// injects it into the generated Info.plists; this type reads it back from
/// the bundle at runtime. For SwiftPM test runs (no bundle) it falls back to
/// the `VOLTIO_TEAM_ID` environment variable, which the test runner sets.
public enum AppGroupConfiguration {
    /// Apple Team ID injected at build time (10-char uppercase string).
    /// Empty string in unbundled contexts where no injection happened.
    public static let teamID: String = {
        // Bundle-based lookup works in the app and the appex; the host app's
        // bundle is visible to the extension via the parent-bundle relationship.
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["VOLTIO_TEAM_ID"], !env.isEmpty {
            return env
        }
        #endif
        for bundle in [Bundle.main, Bundle(for: BundleToken.self)] {
            if let id = bundle.object(forInfoDictionaryKey: "VoltioTeamID") as? String, !id.isEmpty {
                return id
            }
        }
        return ""
    }()

    /// Full App Group identifier: `TEAMID.group.com.voltio.app`.
    /// Empty when no Team ID is configured (tests, tooling) — callers treat
    /// that as "widgets unavailable" rather than crashing.
    public static var appGroupID: String {
        teamID.isEmpty ? "" : "\(teamID).group.com.voltio.app"
    }
}

/// Anchor for `Bundle(for:)` — locates THIS module's bundle regardless of
/// whether the caller is the host app or the widget extension.
private final class BundleToken {}
