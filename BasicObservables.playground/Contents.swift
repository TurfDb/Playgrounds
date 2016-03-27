import Turf

//: The model we will write to the database
struct User {
    let firstName: String
    let lastName: String
}

//: The collection we will store `User`s in
final class UsersCollection: Collection {
    // `Collection`s are strongly typed to contain only a single type of value
    typealias Value = User

    // This is the unique name for the collection
    let name = "Users"
    // A schema version is used for migrations. See <Migrations>
    let schemaVersion = UInt64(1)
    // See <Performance enhancements>
    let valueCacheSize: Int? = nil

    // All database knowledge is kept out of the model and defined within the `Collection`.
    // Here we describe how to persist a `User`.
    func serializeValue(value: User) -> NSData {
        let dictionaryRepresentation: [String: AnyObject] = [
            "firstName": value.firstName,
            "lastName": value.lastName
        ]

        return try! NSJSONSerialization.dataWithJSONObject(dictionaryRepresentation, options: [])
    }

    // And here we describe how to deserialize our persisted user.
    func deserializeValue(data: NSData) -> Value? {
        let json = try! NSJSONSerialization.JSONObjectWithData(data, options: [])

        guard let
            firstName = json["firstName"] as? String,
            lastName = json["lastName"] as? String else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName)
    }

    // When intializing a database we must set up the collection by registering it and any
    // possible extensions. See <Secondary indexing>
    func setUp(transaction: ReadWriteTransaction) throws {
        // This line is required for every collection you set up
        try transaction.registerCollection(self)
    }
}

//: A container that holds all collections associated with a `Database` instance
final class Collections: CollectionsContainer {
    let users = UsersCollection()

    // We must set up each collection defined within the container
    func setUpCollections(transaction transaction: ReadWriteTransaction) throws {
        try users.setUp(transaction)
    }
}

//: Create a new database
let collections = Collections()
let database = try! Database(path: "BasicObservable.sqlite", collections: collections)
//: Open a connection which we can use to read and write values to `database`
let connection = try! database.newConnection()
//: Open a special kind of connection which we can use to observe changes to `database`
let observingConnection = try! database.newObservingConnection()

//: We'll watch for changes to the `users` collection in `database`.
let disposable =
    observingConnection.observeCollection(collections.users)
    .didChange { (userCollection, changeSet) in
        print("Changes for Bill? \(changeSet.hasChangeForKey("BillMurray"))")
        print("All changes", changeSet.changes)
    }

//: Lets write some changes to the database. See <Basic>. These writes will trigger our didChange callback above
try! connection.readWriteTransaction { transaction in
    let bill = User(firstName: "Bill", lastName: "Murray")
    let tom = User(firstName: "Tom", lastName: "Hanks")

    let usersCollection = transaction.readWrite(collections.users)
    usersCollection.setValue(bill, forKey: "BillMurray")
    usersCollection.setValue(tom, forKey: "TomHanks")
}

//: Dispose of the didChange observer and by disposing ancestors we also dispose of the observedCollection users
disposable.dispose(disposeAncestors: true)
