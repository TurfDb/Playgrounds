//: ## Basic Observables
//: Turf provides a reactive approach to listening for database changes
//: 
import Turf

//: Make sure to check out the Basic playground first - it covers this initial setup
struct User {
    let firstName: String
    let lastName: String
}

final class UsersCollection: Collection {
    typealias Value = User

    let name = "Users"
    let schemaVersion = UInt64(1)
    let valueCacheSize: Int? = nil

    func serializeValue(value: User) -> NSData {
        let dictionaryRepresentation: [String: AnyObject] = [
            "firstName": value.firstName,
            "lastName": value.lastName
        ]

        return try! NSJSONSerialization.dataWithJSONObject(dictionaryRepresentation, options: [])
    }

    func deserializeValue(data: NSData) -> Value? {
        let json = try! NSJSONSerialization.JSONObjectWithData(data, options: [])

        guard let
            firstName = json["firstName"] as? String,
            lastName = json["lastName"] as? String else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName)
    }

    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try transaction.registerCollection(self)
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
    observingConnection.observeCollection(collections.users)
    .didChange { (userCollection, changeSet) in
        print("Changes for Bill? \(changeSet.hasChangeForKey("BillMurray"))")
        print("All changes", changeSet.changes)
    }

//: Lets write some changes to the database. See <Basic>. These writes will trigger our didChange callback above
try! connection.readWriteTransaction { transaction, collections in
    let bill = User(firstName: "Bill", lastName: "Murray")
    let tom = User(firstName: "Tom", lastName: "Hanks")

    let usersCollection = transaction.readWrite(collections.users)
    usersCollection.setValue(bill, forKey: "BillMurray")
    usersCollection.setValue(tom, forKey: "TomHanks")
}

//: Dispose of the didChange observer and by disposing ancestors we also dispose of the observedCollection users.
//: This step is optional here as the observers will be disposed of when they go out of scope and get dealloc'd
disposable.dispose(disposeAncestors: true)
