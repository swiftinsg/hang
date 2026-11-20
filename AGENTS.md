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
│               └── time: Timestamp
│
└── groups (collection)
    └── Auto-ID (document)
        ├── inviteCode: String
        ├── name: String
        ├── desc: String
        ├── people: [DocumentReference]
        └── events (subcollection)
            └── eventID (document)
                ├── name: String
                ├── desc: String
                ├── location: String
                └── time: Timestamp

