
//: We're going to walk through how to save a `User` in Turf and then read them back out of the database
import Turf

//: The model we will write to the database
struct User {
    let firstName: String
    let lastName: String
}

//: One of the main goals for Turf is to keep database responsibility out of the model. A common complaint with Core Data and Realm is that you must subclass from something, immediately leaking knowledge. With Turf, you don't even have to conform to a protocol. All database knowledge is kept out of the model and defined within a class that conforms to `Collection`.
//: Collections in Turf are also schemaless.
final class UsersCollection: TurfCollection {
    // `Collection`s are strongly typed to contain only a single type of value
    typealias Value = User

    // This is the unique name for the collection
    let name = "Users"
    // A schema version is used for migrations. See <Migrations>
    let schemaVersion = UInt64(1)
    // See <PerformanceEnhancements>
    let valueCacheSize: Int? = nil

    // Here we describe how to persist a `User`.
    func serialize(value: User) -> Data {
        let dictionaryRepresentation: [String: Any] = [
            "firstName": value.firstName,
            "lastName": value.lastName
        ]

        return try! JSONSerialization.data(withJSONObject: dictionaryRepresentation, options: [])
    }

    // And here we describe how to deserialize our persisted user.
    func deserialize(data: Data) -> Value? {
        let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        guard
            let firstName = json["firstName"] as? String,
            let lastName = json["lastName"] as? String else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName)
    }

    // When intializing a database we must set up the collection by registering it and any possible extensions. See <BasicSecondaryIndexing>
    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        // This line is required for every collection you set up
        try transaction.register(collection: self)
    }
}

//: A container that holds all collections associated with a `Database` instance
final class Collections: CollectionsContainer {
    let users = UsersCollection()

    // We must set up each collection defined within the container
    func setUpCollections<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try users.setUp(using: transaction)
    }
}

//: Create a new database and open a connection to it
let collections = Collections()
let database = try! Database(path: "Basic.sqlite", collections: collections)
let connection = try! database.newConnection()

//: A `ReadWriteTransaction` allows you to modify the database in a transactional way. That is
//: if the app crashes, any changes made inside the transaction will not be persisted.
//: Grouping multiple reads and writes per transaction is also more performant than many small
//: transactions.
struct Test { }
try! connection.readWriteTransaction { transaction, collections in
    let bill = User(firstName: "Bill", lastName: "Murray")
    // Create a writable view of the Users collection
    let usersCollection = transaction.readWrite(collections.users)
    // `usersCollection` and `transaction` are only valid within the current closure's scope
    usersCollection.set(value: bill, forKey: "BillMurray")
}

try! connection.readWriteTransaction { transaction, collections in
    // Create a read only view of the Users collection
    let usersCollection = transaction.readOnly(collections.users)
    // `usersCollection` and `transaction` are only valid within the current closure's scope

    // Fetch a value by primary key from the users collection
    if let bill = usersCollection.value(for: "BillMurray") {
        print("Found \(bill.firstName) \(bill.lastName)!")
    } else {
        print("No Bill")
    }
}

//: We used a `ReadWriteTransaction` to read the values back out above, but to provide stronger guarantees and utilise the type system, we can create a `ReadTransaction` that is read only.

try! connection.readTransaction { transaction, collections in
    // Create a read only view of the Users collection
    let usersCollection = transaction.readOnly(collections.users)
    // This line wont compile!
//    let usersCollection = transaction.readWrite(collections.users)

    if let bill = usersCollection.value(for: "BillMurray") {
        print("Found \(bill.firstName) \(bill.lastName)!")
    } else {
        print("No Bill")
    }
}


