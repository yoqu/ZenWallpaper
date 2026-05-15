import AppKit
import Foundation

/// Stable identity for a connected display. The position in `NSScreen.screens`
/// shifts when you hot-plug, so we key persisted state off the display's
/// Core Graphics UUID (which survives reboots and dock shuffles).
struct DisplayIdentity: Identifiable, Hashable, Sendable {
    let uuid: String
    let displayID: CGDirectDisplayID
    let localizedName: String
    let frame: CGRect
    let backingScaleFactor: CGFloat
    let isMain: Bool

    var id: String { uuid }

    // Custom Hashable: identity is the UUID, full stop. We deliberately ignore
    // `frame` / `backingScaleFactor` because they can drift by a sub-pixel
    // during display reconfiguration — synthesized Hashable would then produce
    // different hashes for what is semantically the same display, and SwiftUI
    // diff caches would crash with
    // KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS.
    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    static func == (lhs: DisplayIdentity, rhs: DisplayIdentity) -> Bool {
        lhs.uuid == rhs.uuid
    }

    /// Pixel-accurate size string ("3024×1964") for the Settings display list.
    var pixelDescription: String {
        let pw = Int(frame.width * backingScaleFactor)
        let ph = Int(frame.height * backingScaleFactor)
        return "\(pw)×\(ph)"
    }

    /// Nearest aspect-ratio slug — same buckets the prompt API expects.
    var aspectRatioSlug: String {
        let ratio = Double(frame.width / max(frame.height, 1))
        return Self.closestRatioSlug(for: ratio)
    }

    /// Resolve the underlying `NSScreen` if it's still connected. Returns nil
    /// if the display was unplugged between when this identity was captured
    /// and now.
    var screen: NSScreen? {
        NSScreen.screens.first { Self.displayID(for: $0) == displayID }
    }

    // MARK: Helpers

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    static func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuidRef) as String
    }

    /// Build an identity for the given screen. Mirrored slaves are folded into
    /// their master — calling `setDesktopImageURL` on a mirrored slave is a
    /// silent no-op anyway, so we don't want duplicate entries in the UI.
    static func from(_ screen: NSScreen) -> DisplayIdentity? {
        guard let displayID = displayID(for: screen),
              let ownUUID = uuid(for: displayID) else {
            return nil
        }
        let mirroredOf = CGDisplayMirrorsDisplay(displayID)
        let canonicalID = mirroredOf != 0 ? mirroredOf : displayID
        let canonicalUUID = canonicalID == displayID
            ? ownUUID
            : (uuid(for: canonicalID) ?? ownUUID)
        let mainID = (NSScreen.main).flatMap(displayID(for:))
        return DisplayIdentity(
            uuid: canonicalUUID,
            displayID: displayID,
            localizedName: screen.localizedName,
            frame: screen.frame,
            backingScaleFactor: screen.backingScaleFactor,
            isMain: displayID == mainID
        )
    }

    /// All physically distinct connected displays, mirrored duplicates folded
    /// out. Order matches `NSScreen.screens`, so the main display is usually
    /// (not always) first.
    static func allConnected() -> [DisplayIdentity] {
        var seen: Set<String> = []
        var result: [DisplayIdentity] = []
        for screen in NSScreen.screens {
            guard let identity = from(screen) else { continue }
            if seen.insert(identity.uuid).inserted {
                result.append(identity)
            }
        }
        return result
    }

    static func closestRatioSlug(for ratio: Double) -> String {
        struct Candidate { let slug: String; let value: Double }
        let candidates: [Candidate] = [
            Candidate(slug: "16:9", value: 16.0 / 9.0),
            Candidate(slug: "3:2",  value: 3.0 / 2.0),
            Candidate(slug: "4:3",  value: 4.0 / 3.0),
            Candidate(slug: "5:4",  value: 5.0 / 4.0),
            Candidate(slug: "1:1",  value: 1.0),
            Candidate(slug: "4:5",  value: 4.0 / 5.0),
            Candidate(slug: "3:4",  value: 3.0 / 4.0),
            Candidate(slug: "2:3",  value: 2.0 / 3.0),
            Candidate(slug: "9:16", value: 9.0 / 16.0)
        ]
        var best = candidates[0]
        var bestDelta = abs(log(best.value / ratio))
        for c in candidates.dropFirst() {
            let d = abs(log(c.value / ratio))
            if d < bestDelta { best = c; bestDelta = d }
        }
        return best.slug
    }
}
