//: ## Intermediate Secondary Indexing
//: There is virtually no changes in set up between this and basic. Here we will show the power of strongly typed predicates for indexing optional values.
import Turf

struct User {
    let firstName: String
    let lastName: String
    let isActive: Bool
    let email: String?
}

final class UsersCollection: Collection, IndexedCollection {
    typealias Value = User

    let name = "Users"
    let schemaVersion = UInt64(1)
    let valueCacheSize: Int? = nil

    let index: SecondaryIndex<UsersCollection, IndexedProperties>
    let indexed = IndexedProperties()

    let associatedExtensions: [Extension]

    init() {
        index = SecondaryIndex(collectionName: name, properties: indexed, version: 0)
        associatedExtensions = [index]
        index.collection = self
    }

    func serializeValue(value: User) -> NSData {
        var dictionaryRepresentation: [String: AnyObject] = [
            "firstName": value.firstName,
            "lastName": value.lastName,
            "isActive": value.isActive,
        ]
        if let email = value.email { dictionaryRepresentation["email"] = email }

        return try! NSJSONSerialization.dataWithJSONObject(dictionaryRepresentation, options: [])
    }

    func deserializeValue(data: NSData) -> Value? {
        let json = try! NSJSONSerialization.JSONObjectWithData(data, options: [])

        guard let
            firstName = json["firstName"] as? String,
            lastName = json["lastName"] as? String,
            isActive = json["isActive"] as? Bool  else {
                return nil
        }
        return User(firstName: firstName, lastName: lastName, isActive: isActive, email: json["email"] as? String)
    }

    func setUp(transaction: ReadWriteTransaction) throws {
        try transaction.registerCollection(self)
        try transaction.registerExtension(index)
    }

//: We'll define a few extra indexed properties
    struct IndexedProperties: Turf.IndexedProperties {

        let isActive = IndexedProperty<UsersCollection, Bool>(name: "isActive") { user in
            return user.isActive
        }

//: Due to limits with Swift type constraints, for now, optionals need converted to an SQLiteOptional type as shown here
        let email = IndexedProperty<UsersCollection, SQLiteOptional<String>>(name: "email") { user in
            return user.email.toSQLite()
        }

        var allProperties: [IndexedPropertyFromCollection<UsersCollection>] {
            return [isActive.lift(), email.lift()]
        }
    }
}

final class Collections: CollectionsContainer {
    let users = UsersCollection()

    func setUpCollections(transaction transaction: ReadWriteTransaction) throws {
        try users.setUp(transaction)
    }
}

//: Create a new database and open a connection to it
let collections = Collections()
let database = try! Database(path: "IntermediateSecondaryIndexing.sqlite", collections: collections)
let connection = try! database.newConnection()

//: Here we'll add a few rows that we can query
try! connection.readWriteTransaction { transaction in
    let usersCollection = transaction.readWrite(collections.users)

    usersCollection.removeAllValues()

    usersCollection.setValue(
        User(firstName: "Amy", lastName: "Adams", isActive: true, email: nil),
        forKey: "AmyAdams")

    usersCollection.setValue(
        User(firstName: "Jennifer", lastName: "Laurence", isActive: false, email: "jen@somewhere.com"),
        forKey: "JenniferLaurence")

    usersCollection.setValue(
        User(firstName: "Whoopi", lastName: "Goldberg", isActive: false, email: "whoopi@example.com"),
        forKey: "WhoopiGoldberg")

    usersCollection.setValue(
        User(firstName: "Tom", lastName: "Hanks", isActive: false, email: "tom@example.com"),
        forKey: "TomHanks")

    usersCollection.setValue(
        User(firstName: "Bill", lastName: "Murray", isActive: true, email: "bill@example.com"),
        forKey: "BillMurray")
}

//: Lets query the collection
try! connection.readTransaction { transaction in
    let usersCollection = transaction.readOnly(collections.users)

    let activeUsersWithoutAnEmail = usersCollection
        .findValuesWhere(
            usersCollection.indexed.isActive.equals(true)
            .and(usersCollection.indexed.email.isNil())
        )

    // Doesn't compile because isActive is not an `Optional`
//    let predicate = usersCollection.indexed.isActive.isNil()

    let usersWithAnEmailHostedAtExampleDotCom = usersCollection
        .findValuesWhere(usersCollection.indexed.email.isLike("%@example.com"))
}
