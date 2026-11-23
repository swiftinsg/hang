//
//  AvailabilityStore.swift
//  Hang
//
//  Reads the busy blocks other members published, and nothing else.
//
//  PRIVACY CONTRACT — the receiving side.
//
//  There is no title, note, location or event id in the documents this store
//  reads, and no field here could hold one. Only `days[].date` and
//  `days[].intervals` are decoded; extra keys are ignored. Everyone else's
//  calendar stays on their phone.
//

import FirebaseFirestore
import Foundation
import Observation

@Observable
final class AvailabilityStore {
    static let shared = AvailabilityStore()

    /// groupID → uid → availability. A member with no busy time still gets an
    /// entry with an empty interval list, so "sharing and free" is
    /// distinguishable from "not sharing at all".
    private(set) var byGroup: [String: [String: MemberAvailability]] = [:]

    private(set) var errorMessage: String?

    @ObservationIgnored private var listeners: [String: ListenerRegistration] = [:]

    /// Resolved lazily so a preview store can exist without a Firebase app.
    private var db: Firestore { Firestore.firestore() }

    private init() {}

    // MARK: - Listening

    /// Brings the live listeners in line with the visible groups.
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
        guard !groupID.isEmpty, listeners[groupID] == nil else { return }

        listeners[groupID] = db
            .collection(Path.Firestore.Groups)
            .document(groupID)
            .collection(Path.Firestore.Availability)
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

    /// Forces a fresh read for pull-to-refresh. Live listeners stay in place,
    /// so later updates still arrive without another manual refresh.
    func refresh() async {
        for groupID in Array(listeners.keys) {
            do {
                let snapshot = try await db
                    .collection(Path.Firestore.Groups)
                    .document(groupID)
                    .collection(Path.Firestore.Availability)
                    .getDocuments()

                var members: [String: MemberAvailability] = [:]
                for document in snapshot.documents {
                    members[document.documentID] = Self.decode(document)
                }

                byGroup[groupID] = members
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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

    /// Whether this member has published anything at all for the group.
    func isSharing(_ uid: String, inGroup groupID: String) -> Bool {
        byGroup[groupID]?[uid] != nil
    }

    // MARK: - Decoding

    private static func decode(_ document: QueryDocumentSnapshot) -> MemberAvailability {
        let data = document.data()
        let timeZone =
            TimeZone(identifier: data["timezoneIdentifier"] as? String ?? "")
            ?? .current
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()

        // Only date + number pairs are read. Any other key a document might
        // contain is ignored, so no title can reach the UI from here.
        let intervals = (data["days"] as? [[String: Any]] ?? []).flatMap { entry in
            BusyDay(date: entry["date"] as? String ?? "", intervals: intPairs(from: entry["intervals"]))
                .dateIntervals()
        }

        return MemberAvailability(
            intervals: intervals.sorted { $0.start < $1.start },
            updatedAt: updatedAt,
            timezone: timeZone
        )
    }

    /// The wire format is one flat list of milliseconds: start, end, start,
    /// end, ... Rebuild the pairs here so the rest of the app keeps working
    /// with `DateInterval` values.
    private static func intPairs(from raw: Any?) -> [[Int]] {
        guard let values = raw as? [Any] else { return [] }
        let numbers = values.compactMap { ($0 as? NSNumber)?.intValue }
        guard numbers.count % 2 == 0 else { return [] }

        return stride(from: 0, to: numbers.count, by: 2).map {
            [numbers[$0], numbers[$0 + 1]]
        }
    }
}
