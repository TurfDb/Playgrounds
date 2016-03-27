//: ## Basic Secondary Indexing
//: A secondary index is a database extension which allows you to efficiently query the database.
//: We simply register the extension with a collection and define which properties we would like to query on and how to read them.
import Turf

//: The model we will write to the database
struct User {
    let firstName: String
    let lastName: String
    let isActive: Bool
}

//: The collection we will store `User`s in.
//: By conforming to `IndexedCollection` it will expose methods on `ReadCollection<UsersCollection>` which allow us to perform indexed queries. It will also expose methods on `ReadWriteCollection<UsersCollection>` which we'll  touch on near the end of this playground.
final class UsersCollection: Collection, IndexedCollection {
    // `Collection`s are strongly typed to contain only a single type of value
    typealias Value = User

    // This is the unique name for the collection
    let name = "Users"
    // A schema version is used for migrations. See <Migrations>
    let schemaVersion = UInt64(1)
    // See <Performance enhancements>
    let valueCacheSize: Int? = nil

    //: We must define what collection and properties are indexed when creating a new secondary index
    let index: SecondaryIndex<UsersCollection, IndexedProperties>
    let indexed = IndexedProperties()

    //: We also have to keep a list of extensions that are to be executed on mutation
    let associatedExtensions: [Extension]

    init() {
        index = SecondaryIndex(collectionName: name, properties: indexed, version: 0)
        associatedExtensions = [index]

        //: By setting the `collection` the secondary index can build itself if there are already values in the `Users` collection
        index.collection = self
    }

    // All database knowledge is kept out of the model and defined within the `Collection`.
    // Here we describe how to persist a `User`.
    func serializeValue(value: User) -> NSData {
        let dictionaryRepresentation: [String: AnyObject] = [
            "firstName": value.firstName,
            "lastName": value.lastName,
            "isActive": value.isActive
        ]

        return try! NSJSONSerialization.dataWithJSONObject(dictionaryRepresentation, options: [])
    }

    // And here we describe how to deserialize our persisted user.
    func deserializeValue(data: NSData) -> Value? {
        let json = try! NSJSONSerialization.JSONObjectWithData(data, options: [])

        guard let
            firstName = json["firstName"] as? String,
            lastName = json["lastName"] as? String,
            isActive = json["isActive"] as? Bool else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName, isActive: isActive)
    }

    // When intializing a database we must set up the collection by registering it and any
    // possible extensions. See <Secondary indexing>
    func setUp(transaction: ReadWriteTransaction) throws {
        // This line is required for every collection you set up
        try transaction.registerCollection(self)
        //: We must register the extension
        try transaction.registerExtension(index)
    }

    //: We define the properties of a `User` that are indexed and therefore queryable
    struct IndexedProperties: Turf.IndexedProperties {
        let isActive = IndexedProperty<UsersCollection, Bool>(name: "isActive") { return $0.isActive }

        var allProperties: [IndexedPropertyFromCollection<UsersCollection>] {
            // We must list all the properties that are indexed to register them in SQLite
            // `.lift()` is currently a work around for the Swift type system.
            return [isActive.lift()]
        }
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
let database = try! Database(path: "BasicSecondaryIndexing.sqlite", collections: collections)
let connection = try! database.newConnection()

//: Here we'll add a few rows that we can query
try! connection.readWriteTransaction { transaction in
    let usersCollection = transaction.readWrite(collections.users)

    usersCollection.setValue(
        User(firstName: "Amy", lastName: "Adams", isActive: true),
        forKey: "AmyAdams")

    usersCollection.setValue(
        User(firstName: "Tom", lastName: "Hanks", isActive: false),
        forKey: "TomHanks")

    usersCollection.setValue(
        User(firstName: "Bill", lastName: "Murray", isActive: true),
        forKey: "BillMurray")
}

//: Lets query the collection for active and inactive users
try! connection.readTransaction { transaction in
    let usersCollection = transaction.readOnly(collections.users)
    let count = usersCollection.countValuesWhere(usersCollection.indexed.isActive.equals(true))
    let activeUsers = usersCollection.findValuesWhere(usersCollection.indexed.isActive.equals(true))
    let inactiveUsers = usersCollection.findValuesWhere(usersCollection.indexed.isActive.equals(false))
}

//: Here we'll delete inactive users
try! connection.readWriteTransaction { transaction in
    let usersCollection = transaction.readWrite(collections.users)

    usersCollection.removeValuesWhere(usersCollection.indexed.isActive.equals(false))
}

//: Lets check if there are any inactive users left
try! connection.readTransaction { transaction in
    let usersCollection = transaction.readOnly(collections.users)
    let activeUsers = usersCollection.findValuesWhere(usersCollection.indexed.isActive.equals(true))
    let inactiveUsers = usersCollection.findValuesWhere(usersCollection.indexed.isActive.equals(false))
}

