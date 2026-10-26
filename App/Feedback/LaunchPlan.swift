// App/Feedback/LaunchPlan.swift
import Foundation

/// Fork: what a starting copy of Nextshot does when it is not alone.
///
/// Finder cannot replace a running app: a drag over a running Nextshot ends
/// with "The operation can't be completed because the item is in use"
/// (tested 2026-10-25). So the new copy on the disk image does the update
/// itself, and the newest build always wins (Drew, 2026-10-25, items 1.2 and
/// 1.4). Foundation only, so the rules stay easy to test.
enum LaunchPlan: Equatable {
    /// Start normally.
    case run
    /// This copy is the newest build. Ask these older copies to quit, then start.
    case quitOlderCopies([pid_t])
    /// Another copy is the same build or newer. Bring it to the front and exit.
    case yield(to: pid_t)
    /// This copy runs from a disk image and is newer than the installed copy.
    /// Offer to install it.
    case offerInstall
    /// This copy runs from a disk image and the installed copy is the same
    /// build or newer. Open the installed copy and exit.
    case openInstalled

    /// A Nextshot build, ordered by build number first. The build number is
    /// the commit count on main at the release commit, so releases rise in
    /// order (`docs/decisions/2026-10-25-versioning-and-releases.md`). The
    /// version text is for display and breaks a tie only. Until 2026-10-25 the
    /// order went by version date first, because the dev builds and the
    /// releases shared a bundle ID and counted commits on different branches:
    /// a local trial build was 665 and the release from a later commit was
    /// 618. Nextshot Dev has its own bundle ID, so that mix cannot happen. A
    /// copy still compares correctly with the date builds in the field: the
    /// last of them, 2026.10.24, is build 524.
    struct Build: Comparable, CustomStringConvertible {
        var version: [Int]
        var number: Int

        /// `version` is CFBundleShortVersionString, for example "0.3.0".
        init(version: String, number: Int) {
            self.version = version.split(separator: ".").map { Int($0) ?? 0 }
            self.number = number
        }

        static let unknown = Build(version: "", number: 0)

        static func < (a: Build, b: Build) -> Bool {
            if a.number != b.number { return a.number < b.number }
            return a.version.lexicographicallyPrecedes(b.version)
        }

        var description: String {
            "\(version.map(String.init).joined(separator: ".")) (\(number))"
        }
    }

    struct Copy: Equatable {
        var pid: pid_t
        var build: Build
        var launchDate: Date
        /// True for a copy on a disk image, or one that macOS moved to a
        /// read-only place before launch (App Translocation).
        var onReadOnlyVolume: Bool
    }

    /// `others` are the other running copies with this bundle ID.
    /// `installedBuild` is the build of the copy where an install would go,
    /// or nil when there is none.
    static func decide(me: Copy, others: [Copy], installedBuild: Build?) -> LaunchPlan {
        if me.onReadOnlyVolume {
            let installedCopies = others.filter { !$0.onReadOnlyVolume }
            let newestElsewhere = (installedCopies.map(\.build) + [installedBuild].compactMap { $0 }).max()
            if newestElsewhere.map({ me.build > $0 }) ?? true {
                return .offerInstall
            }
            if let keeper = keeper(of: installedCopies) {
                return .yield(to: keeper.pid)
            }
            return .openInstalled
        }

        guard let keeper = keeper(of: others + [me]) else { return .run }
        if keeper.pid != me.pid {
            return .yield(to: keeper.pid)
        }
        // A copy of the same build sees this one as the keeper and exits by
        // itself, so only older builds get a quit request.
        let older = others.filter { $0.build < me.build }.map(\.pid)
        return older.isEmpty ? .run : .quitOlderCopies(older)
    }

    /// The newest build wins. Among copies of that build, the oldest wins:
    /// two copies that start in the same second both see each other, so only
    /// one of them may stay.
    static func keeper(of copies: [Copy]) -> Copy? {
        copies.min { a, b in
            if a.build != b.build { return a.build > b.build }
            if a.launchDate != b.launchDate { return a.launchDate < b.launchDate }
            return a.pid < b.pid
        }
    }
}
