//: ## Intermediate Observables
//: Here we'll follow on from BasicObservables and show their transactionality which allows us to fetch other values when something changes.
import Turf

//: The model we will write to the database
struct User {
    let firstName: String
    let lastName: String
    let isCurrent: Bool
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
            "lastName": value.lastName,
            "isCurrent": value.isCurrent
        ]

        return try! NSJSONSerialization.dataWithJSONObject(dictionaryRepresentation, options: [])
    }

    // And here we describe how to deserialize our persisted user.
    func deserializeValue(data: NSData) -> Value? {
        let json = try! NSJSONSerialization.JSONObjectWithData(data, options: [])

        guard let
            firstName = json["firstName"] as? String,
            lastName = json["lastName"] as? String,
            isCurrent = json["isCurrent"] as? Bool else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName, isCurrent: isCurrent)
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

//: We'll watch for changes to the `users` collection and grab a current user.
let currentUser = ObserverOf<User?>(initalValue: nil)
let disposable =
    observingConnection.observeCollection(collections.users)
        .didChange { (userCollection, changeSet) in
            guard let collection = userCollection else { return }

            // `collection` is a snapshot of the database at the time the observed collection changed.
            // It uses an implicit `ReadTransaction` under the hood meaning that any subsequent changes 
            // keeps the transactionality of performing fetches here.

            let current = collection.allValues.filter { user -> Bool in
                return user.isCurrent
            }.first

            currentUser.setValue(current, fromTransaction: collection.readTransaction)
        }

//: `currentUser.value` will now be updated any time the `users` collection is written to
let currentUserDisposable = currentUser.didChange { (currentUser, changedOnTransaction) in
    if let currentUser = currentUser {
        print("The current user is \(currentUser.firstName) \(currentUser.lastName)")
    } else {
        print("There is no current user")
    }
}

//: Lets write some changes to the database. See <Basic>. 
//: These writes will trigger our observable collection `didChange` callback above. See <BasicObservables>. When setting `currentUser` it will trigger our `currentUser.didChange` callback.
try! connection.readWriteTransaction { transaction in
    // Play around changing `isCurrent` and check out the output above when there is no current user!
    let bill = User(firstName: "Bill", lastName: "Murray", isCurrent: false)
    let tom = User(firstName: "Tom", lastName: "Hanks", isCurrent: true)

    let usersCollection = transaction.readWrite(collections.users)
    usersCollection.setValue(bill, forKey: "BillMurray")
    usersCollection.setValue(tom, forKey: "TomHanks")
}

// We could pass `true` here and it would have the same effect as the second `dispose` below
currentUserDisposable.dispose(disposeAncestors: false)
disposable.dispose(disposeAncestors: true)
