//
//  AvailabilityStore.swift
//  Hang
//
//  Reads the busy blocks other members published, and nothing else.
//
//  PRIVACY CONTRACT — the receiving side.
//
//  There is no title, note, location or event id in the documents this store
//  reads, and no field here could hold one. A payload that somehow contained
//  extra keys would simply be ignored; only `days[].date` and
//  `days[].intervals` are ever decoded. Everyone else's calendar stays on
//  their phone.
//

import FirebaseFirestore
import Foundation
import Observation

@Observable
final class AvailabilityStore {
    /// groupID → uid → availability. A member with no busy time still gets an
    /// entry with an empty interval list, so "sharing and free" is
    /// distinguishable from "not sharing at all".
    private(set) var byGroup: [String: [String: MemberAvailability]] = [:]

    /// Last listener error, surfaced so the UI can say something went wrong
    /// instead of silently showing empty lanes.
    private(set) var errorMessage: String?

    @ObservationIgnored private var listeners: [String: ListenerRegistration] = [:]

    /// Resolved lazily so a preview store can exist without a Firebase app.
    private var db: Firestore { Firestore.firestore() }

    // MARK: - Listening

    /// Brings the set of live listeners in line with the visible groups:
    /// starts new ones, stops the ones for groups that were left or deleted.
    func sync(groupIDs: [String]) {
        let live = Set(groupIDs)

        for key in Array(listeners.keys) where !live.contains(key) {
            stop(groupID: key)
        }
        for groupID in groupIDs {
            listen(groupID: groupID)
        }
    }

    func listen(groupID: String) {
        guard listeners[groupID] == nil else { return }

        listeners[groupID] = db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.availability)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                    return
                }
                guard let snapshot else { return }

                var members: [String: MemberAvailability] = [:]
                for document in snapshot.documents {
                    members[document.documentID] = Self.decode(document)
                }

                Task { @MainActor in
                    self.byGroup[groupID] = members
                    self.errorMessage = nil
                }
            }
    }

    func stop(groupID: String) {
        listeners.removeValue(forKey: groupID)?.remove()
        byGroup[groupID] = nil
    }

    func stopAll() {
        for key in Array(listeners.keys) {
            listeners.removeValue(forKey: key)?.remove()
        }
        byGroup = [:]
    }

    // MARK: - Reading

    /// What `AvailabilityCalculator.sharedBusy` wants.
    func busyIntervals(inGroup groupID: String) -> [String: [DateInterval]] {
        (byGroup[groupID] ?? [:]).mapValues(\.intervals)
    }

    /// What `AvailabilityCalculator.sharedUpdatedAt` wants.
    func updatedAt(inGroup groupID: String) -> [String: Date] {
        (byGroup[groupID] ?? [:]).compactMapValues(\.updatedAt)
    }

    /// Called when a member has published nothing at all for this group.
    func isSharing(_ uid: String, inGroup groupID: String) -> Bool {
        byGroup[groupID]?[uid] != nil
    }

    // MARK: - Decoding

    private static func decode(_ document: QueryDocumentSnapshot) -> MemberAvailability {
        let data = document.data()
        let timeZone = TimeZone(identifier: data["timezoneIdentifier"] as? String ?? "") ?? .current
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()

        let intervals = (data["days"] as? [[String: Any]] ?? []).flatMap { entry -> [DateInterval] in
            let date = entry["date"] as? String ?? ""
            let pairs = intPairs(from: entry["intervals"])
            return BusyDay(date: date, intervals: pairs).dateIntervals()
        }

        return MemberAvailability(
            intervals: intervals.sorted { $0.start < $1.start },
            updatedAt: updatedAt,
            timezone: timeZone
        )
    }

    /// Firestore hands back `[Any]` of `[Any]` of `NSNumber`; coerce step by
    /// step rather than gamble on an `[[Int]]` bridge.
    private static func intPairs(from raw: Any?) -> [[Int]] {
        guard let rows = raw as? [Any] else { return [] }
        return rows.compactMap { row in
            guard let pair = row as? [Any] else { return nil }
            let values = pair.compactMap { ($0 as? NSNumber)?.intValue }
            return values.count == 2 ? values : nil
        }
    }
}

#if DEBUG
extension AvailabilityStore {
    /// Seeded preview store. Mirrors what the listener would have decoded from
    /// Firestore, with no network and no Firebase app.
    static func preview(
        groupID: String = PreviewData.groupID,
        members: [Person] = PreviewData.members
    ) -> AvailabilityStore {
        let store = AvailabilityStore()
        store.byGroup[groupID] = PreviewData.availability(for: members)
        return store
    }
}
#endif
