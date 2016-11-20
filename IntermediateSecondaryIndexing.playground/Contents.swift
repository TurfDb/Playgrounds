//: ## Intermediate Secondary Indexing
//: There is virtually no changes in set up between this and basic. Here we will show the power of strongly typed predicates for indexing optional values.
import Turf

struct User {
    let firstName: String
    let lastName: String
    let isActive: Bool
    let email: String?
}

final class UsersCollection: TurfCollection, IndexedCollection {
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

    func serialize(value: User) -> Data {
        var dictionaryRepresentation: [String: Any] = [
            "firstName": value.firstName,
            "lastName": value.lastName,
            "isActive": value.isActive,
        ]
        dictionaryRepresentation["email"] = value.email

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
        return User(firstName: firstName, lastName: lastName, isActive: isActive, email: json["email"] as? String)
    }

    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try transaction.register(collection: self)
        try transaction.register(extension: index)
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

    func setUpCollections<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try users.setUp(using: transaction)
    }
}

//: Create a new database and open a connection to it
let collections = Collections()
let database = try! Database(path: "IntermediateSecondaryIndexing.sqlite", collections: collections)
let connection = try! database.newConnection()

//: Here we'll add a few rows that we can query
try! connection.readWriteTransaction { transaction, collections in
    let usersCollection = transaction.readWrite(collections.users)

    usersCollection.removeAllValues()

    usersCollection.set(
        value: User(firstName: "Amy", lastName: "Adams", isActive: true, email: nil),
        forKey: "AmyAdams"
    )

    usersCollection.set(
        value: User(firstName: "Jennifer", lastName: "Laurence", isActive: false, email: "jen@somewhere.com"),
        forKey: "JenniferLaurence"
    )

    usersCollection.set(
        value: User(firstName: "Whoopi", lastName: "Goldberg", isActive: false, email: "whoopi@example.com"),
        forKey: "WhoopiGoldberg"
    )

    usersCollection.set(
        value: User(firstName: "Tom", lastName: "Hanks", isActive: false, email: "tom@example.com"),
        forKey: "TomHanks"
    )

    usersCollection.set(
        value: User(firstName: "Bill", lastName: "Murray", isActive: true, email: "bill@example.com"),
        forKey: "BillMurray"
    )
}

//: Lets query the collection
try! connection.readTransaction { transaction, collections in
    let usersCollection = transaction.readOnly(collections.users)

    let activeUsersWithoutAnEmail = usersCollection
        .findValues(
            where: usersCollection.indexed.isActive.equals(true)
                    .and(usersCollection.indexed.email.isNil())
        )

    // Doesn't compile because isActive is not an `Optional`
//    let predicate = usersCollection.indexed.isActive.isNil()

    let usersWithAnEmailHostedAtExampleDotCom = usersCollection
        .findValues(where: usersCollection.indexed.email.isNotLike("%@example.com"))

}
