# Firebase schema

Firestore
│
├── users (collection)
│   └── Apple generated UID (document)
│       ├── userId: String  // TODO: REMOVE??
│       ├── username: String
│       ├── reminderPreference: String  // "none" | "1day" | "2hours"; per-user global reminder for ALL events
│       ├── profilePicture: String  // "initial" (first letter of username) or a profilePictures asset name
│       ├── groupsIn: [DocumentReference]
│       ├── calendar (subcollection)
│       │   └── entryID (document)
│       │       ├── name: String
│       │       ├── desc: String
│       │       ├── location: String
│       │       ├── time: Timestamp
│       │       └── endTime: Timestamp
│       └── notifications (subcollection)  // group activity for this member
│           └── autoID (document)
│               ├── kind: String  // "eventEdited"
│               ├── title: String  // "<event name> has been edited"
│               ├── body: String  // "<event name> in group <group name> has been edited"
│               ├── groupID: String
│               ├── eventID: String
│               └── createdAt: Timestamp
│
└── groups (collection)
    └── Auto-ID (document)
        ├── inviteCode: String
        ├── name: String
        ├── desc: String
        ├── people: [DocumentReference]
        ├── memberNames: { uid: username, ... }  // display names shared with the group
        ├── memberProfilePictures: { uid: picture, ... }  // avatars shared with the group; values match profilePicture above
        ├── eventColor: String  // PersonalEventOutlineColor raw value; colour for all this group's events
        ├── events (subcollection)
        │   └── eventID (document)
        │       ├── name: String
        │       ├── desc: String
        │       ├── location: String
        │       ├── time: Timestamp
        │       └── endTime: Timestamp
        └── availability (subcollection)
            └── Apple generated UID (document)  // only the member can write their own
                ├── timezoneIdentifier: String
                ├── updatedAt: Timestamp
                └── days: [{ date: String, intervals: [Int] }]
                    // date = yyyy-MM-dd
                    // intervals = flat [startMillis, endMillis, startMillis, endMillis, ...]
                    // Firestore rejects nested arrays, so pairs are flattened on write.
                    // Busy times only. No titles, notes, locations or event IDs.

