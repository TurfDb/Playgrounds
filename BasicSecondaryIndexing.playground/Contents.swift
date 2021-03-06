//: ## Basic Secondary Indexing
//: A secondary index is a database extension which allows you to efficiently query a collection.
//: We simply register the extension with a collection and define which properties we would like to query on and how to read them.
import Turf

//: The model we will write to the database
struct User {
    let firstName: String
    let lastName: String
    let isActive: Bool
}

//: By conforming to `IndexedCollection` it will expose methods on `ReadCollection<UsersCollection>` which allow us to perform indexed queries. It will also expose methods on `ReadWriteCollection<UsersCollection>` which we'll  touch on near the end of this playground.
final class UsersCollection: TurfCollection, IndexedCollection {
    // `Collection`s are strongly typed to contain only a single type of value
    typealias Value = User

    // This is the unique name for the collection
    let name = "Users"
    // A schema version is used for migrations. See <Migrations>
    let schemaVersion = UInt64(1)
    // See <PerformanceEnhancements>
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

    func serialize(value: User) -> Data {
        let dictionaryRepresentation: [String: Any] = [
            "firstName": value.firstName,
            "lastName": value.lastName,
            "isActive": value.isActive
        ]

        return try! JSONSerialization.data(withJSONObject: dictionaryRepresentation, options: [])
    }

    func deserialize(data: Data) -> Value? {
        let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        guard
            let firstName = json["firstName"] as? String,
            let lastName = json["lastName"] as? String,
            let isActive = json["isActive"] as? Bool else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName, isActive: isActive)
    }

    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try transaction.register(collection: self)
//: We must register the extension
        try transaction.register(extension: index)
    }

//: We define the properties of a `User` that are indexed and therefore queryable
    struct IndexedProperties: Turf.IndexedProperties {

        let isActive = IndexedProperty<UsersCollection, Bool>(name: "isActive") { user -> Bool in
//: This closure is used to grab the value that is indexed from the a model instance
            return user.isActive
        }

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

    func setUpCollections<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try users.setUp(using: transaction)
    }
}

//: Create a new database and open a connection to it
let collections = Collections()
let database = try! Database(path: "BasicSecondaryIndexing.sqlite", collections: collections)
let connection = try! database.newConnection()

//: Here we'll add a few rows that we can query
try! connection.readWriteTransaction { transaction, collections in
    let usersCollection = transaction.readWrite(collections.users)

    usersCollection.set(
        value: User(firstName: "Amy", lastName: "Adams", isActive: true),
        forKey: "AmyAdams"
    )

    usersCollection.set(
        value: User(firstName: "Tom", lastName: "Hanks", isActive: false),
        forKey: "TomHanks"
    )

    usersCollection.set(
        value: User(firstName: "Bill", lastName: "Murray", isActive: true),
        forKey: "BillMurray"
    )
}

//: Lets query the collection for active and inactive users
try! connection.readTransaction { transaction, collections in
    let usersCollection = transaction.readOnly(collections.users)
    let count = usersCollection.countValues(where: usersCollection.indexed.isActive.equals(true))
    let activeUsers = usersCollection.findValues(where: usersCollection.indexed.isActive.equals(true))
    let inactiveUsers = usersCollection.findValues(where: usersCollection.indexed.isActive.equals(false))
}

//: Here we'll delete inactive users
try! connection.readWriteTransaction { transaction, collections in
    let usersCollection = transaction.readWrite(collections.users)
    usersCollection.removeValues(where: usersCollection.indexed.isActive.equals(false))
}

//: Lets check if there are any inactive users left
try! connection.readTransaction { transaction, collections in
    let usersCollection = transaction.readOnly(collections.users)
    let activeUsers = usersCollection.findValues(where: usersCollection.indexed.isActive.equals(true))
    let inactiveUsers = usersCollection.findValues(where: usersCollection.indexed.isActive.equals(false))
}

