//: ## Basic Observables
//: Turf provides a reactive approach to listening for database changes
//: 
import Turf

//: Make sure to check out the Basic playground first - it covers this initial setup
struct User {
    let firstName: String
    let lastName: String
}

final class UsersCollection: TurfCollection {
    typealias Value = User

    let name = "Users"
    let schemaVersion = UInt64(1)
    let valueCacheSize: Int? = nil

    func serialize(value: User) -> Data {
        let dictionaryRepresentation: [String: Any] = [
            "firstName": value.firstName,
            "lastName": value.lastName
        ]

        return try! JSONSerialization.data(withJSONObject: dictionaryRepresentation, options: [])
    }

    func deserialize(data: Data) -> Value? {
        let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        guard
            let firstName = json["firstName"] as? String,
            let lastName = json["lastName"] as? String else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName)
    }

    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try transaction.register(collection: self)
    }
}

final class Collections: CollectionsContainer {
    let users = UsersCollection()

    func setUpCollections<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try users.setUp(using: transaction)
    }
}

//: Create a new database
let collections = Collections()
let database = try! Database(path: "BasicObservables.sqlite", collections: collections)
//: Open a connection which we can use to read and write values to `database`
let connection = try! database.newConnection()
//: Open a special kind of connection which we can use to observe changes to `database`
let observingConnection = try! database.newObservingConnection()

//: Now we can watch for changes to the `users` collection in `database`. The `didChange` callback will be called every time the users collection is modified.
let disposable =
    observingConnection.observe(collection: collections.users)
    .subscribeNext { (userCollection, changeSet) in
        print("Changes for Bill? \(changeSet.hasChange(for: "BillMurray"))")
        print("All changes", changeSet.changes)
    }

//: Lets write some changes to the database. See <Basic>. These writes will trigger our didChange callback above
try! connection.readWriteTransaction { transaction, collections in
    let bill = User(firstName: "Bill", lastName: "Murray")
    let tom = User(firstName: "Tom", lastName: "Hanks")

    let usersCollection = transaction.readWrite(collections.users)
    usersCollection.set(value: bill, forKey: "BillMurray")
    usersCollection.set(value: tom, forKey: "TomHanks")
}

//: Dispose of the observer.
//: This step is optional here as subscriptions will be cleaned up when a `Disposable` gets dealloc'd
disposable.dispose()
