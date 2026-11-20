# Firebase schema

Firestore
│
├── users (collection)
│   └── Apple generated UID (document)
│       ├── userId: String  // TODO: REMOVE??
│       ├── username: String
│       ├── groupsIn: [DocumentReference]
│       └── calendar (subcollection)
│           └── entryID (document)
│               ├── name: String
│               ├── desc: String
│               ├── location: String
│               ├── time: Timestamp
│               └── endTime: Timestamp
│
└── groups (collection)
    └── Auto-ID (document)
        ├── inviteCode: String
        ├── name: String
        ├── desc: String
        ├── people: [DocumentReference]
        ├── memberNames: { uid: username, ... }  // display names shared with the group
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

