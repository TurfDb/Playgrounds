import Turf

//: The model we will write to the database
struct User {
    let firstName: String
    let lastName: String
    let dob: NSDate
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
            "dob": value.dob.timeIntervalSince1970
        ]

        return try! NSJSONSerialization.dataWithJSONObject(dictionaryRepresentation, options: [])
    }

    // And here we describe how to deserialize our persisted user.
    func deserializeValue(data: NSData) -> Value? {
        let json = try! NSJSONSerialization.JSONObjectWithData(data, options: [])

        guard let
            firstName = json["firstName"] as? String,
            lastName = json["lastName"] as? String,
            dob = (json["dob"] as? Double).flatMap({ return NSDate(timeIntervalSince1970: $0) }) else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName, dob: dob)
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

//: Create a new database and open a connection to it
let collections = Collections()
let database = try! Database(path: "Simple.sqlite", collections: collections)
let connection = try! database.newConnection()

//: A `ReadWriteTransaction` allows you to modify the database in a transactional way. That is
//: if the app crashes, any changes made inside the transaction will not be persisted.
//: Grouping multiple reads and writes per transaction is also more performant than many small
//: transactions.
try! connection.readWriteTransaction { transaction in
    let dob = NSDateComponents()
    dob.day = 21
    dob.month = 9
    dob.year = 1950
    let date = NSCalendar.currentCalendar().dateFromComponents(dob)!

    let bill = User(firstName: "Bill", lastName: "Murray", dob: date)

    // Create a writable view of the Users collection
    let usersCollection = transaction.readWrite(collections.users)
    // `usersCollection` and `transaction` are only valid within the current closure's scope
    usersCollection.setValue(bill, forKey: "billMurray")
}

try! connection.readWriteTransaction { transaction in
    // Create a read only view of the Users collection
    let usersCollection = transaction.readOnly(collections.users)
    // `usersCollection` and `transaction` are only valid within the current closure's scope

    // Fetch a value by primary key from the users collection
    if let bill = usersCollection.valueForKey("billMurray") {
        print("Found Bill!")
    } else {
        print("No Bill")
    }
}

