//: ## Intermediate Observables
//: Here we'll follow on from BasicObservables and show their transactionality which allows us to fetch other values when something changes.
import Turf

struct User {
    let firstName: String
    let lastName: String
    let isCurrent: Bool
}

final class UsersCollection: TurfCollection {
    typealias Value = User

    let name = "Users"
    let schemaVersion = UInt64(1)
    let valueCacheSize: Int? = nil

    func serialize(value: User) -> Data {
        let dictionaryRepresentation: [String: Any] = [
            "firstName": value.firstName,
            "lastName": value.lastName,
            "isCurrent": value.isCurrent
        ]

        return try! JSONSerialization.data(withJSONObject: dictionaryRepresentation, options: [])
    }

    func deserialize(data: Data) -> Value? {
        let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        guard
            let firstName = json["firstName"] as? String,
            let lastName = json["lastName"] as? String,
            let isCurrent = json["isCurrent"] as? Bool else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName, isCurrent: isCurrent)
    }

    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try transaction.register(collection: self)
    }
}

final class Collections: CollectionsContainer {
    let users = UsersCollection()

    // We must set up each collection defined within the container
    func setUpCollections<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try users.setUp(using: transaction)
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
let currentUser = observingConnection
    .observe(collection: collections.users)
    //: `map` is a wrapper around `subscribeNext` that gets called when the collection changes.
    //: It produces another observable of the mapped type (in this case `User?`)
    .map { (userCollection, changeSet) -> User? in
        // `userCollection` is a snapshot of the database at the time the observed collection changed.
        // It uses an implicit `ReadTransaction` under the hood meaning that any subsequent changes
        // keeps the transactionality of performing fetches here.

        // `collection.allValues` performs a fetch from the database
        let current = userCollection.allValues.filter { user -> Bool in
            return user.isCurrent
        }.first

        return current
    }


let currentUserDisposable = currentUser.subscribeNext { currentUser in
    if let currentUser = currentUser {
        print("The current user is \(currentUser.firstName) \(currentUser.lastName)")
    } else {
        print("There is no current user")
    }
}

//: Lets write some changes to the database. See <Basic>. 
//: These writes will trigger our observable collection `map` above. See <BasicObservables>. When setting `currentUser` it will trigger our `currentUser.didChange` callback.
try! connection.readWriteTransaction { transaction, collections in
    // Play around changing `isCurrent` and check out the output above when there is no current user!
    let bill = User(firstName: "Bill", lastName: "Murray", isCurrent: false)
    let tom = User(firstName: "Tom", lastName: "Hanks", isCurrent: true)

    let usersCollection = transaction.readWrite(collections.users)
    usersCollection.set(value: bill, forKey: "BillMurray")
    usersCollection.set(value: tom, forKey: "TomHanks")
}

currentUserDisposable.dispose()
