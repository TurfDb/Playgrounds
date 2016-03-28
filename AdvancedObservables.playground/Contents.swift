//: ## Advanced Observables
//: Here we'll see how to combine secondary indexing (see <BasicSecondaryIndexing>) and observables (see <IntermediateObservables> to populate a master-detail style set of table views.
import Turf

//: Lets add an extra model

struct Movie {
    let uuid: String
    let name: String
}

struct User {
    let firstName: String
    let lastName: String
    let isCurrent: Bool

//: A user will now have a list of favourite movies, stored as a list of uuids.
    let favouriteMovies: [String]
}

//: Our new collection for `Movie`s
final class MoviesCollection: Collection {
    typealias Value = Movie

    let name = "Movies"
    let schemaVersion = UInt64(1)
    let valueCacheSize: Int? = nil

    func serializeValue(value: Movie) -> NSData {
        let dictionaryRepresentation: [String: AnyObject] = [
            "uuid": value.uuid,
            "name": value.name
        ]

        return try! NSJSONSerialization.dataWithJSONObject(dictionaryRepresentation, options: [])
    }

    func deserializeValue(data: NSData) -> Movie? {
        let json = try! NSJSONSerialization.JSONObjectWithData(data, options: [])

        guard let
            uuid = json["uuid"] as? String,
            name = json["name"] as? String else {
                return nil
        }
        return Movie(
            uuid: uuid,
            name: name)
    }

    func setUp(transaction: ReadWriteTransaction) throws {
        try transaction.registerCollection(self)
    }
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
        let dictionaryRepresentation: [String: AnyObject] = [
            "firstName": value.firstName,
            "lastName": value.lastName,
            "isCurrent": value.isCurrent,
            "favouriteMovies": value.favouriteMovies
        ]

        return try! NSJSONSerialization.dataWithJSONObject(dictionaryRepresentation, options: [])
    }

    func deserializeValue(data: NSData) -> User? {
        let json = try! NSJSONSerialization.JSONObjectWithData(data, options: [])

        guard let
            firstName = json["firstName"] as? String,
            lastName = json["lastName"] as? String,
            isCurrent = json["isCurrent"] as? Bool,
            favouriteMovieUuids = json["favouriteMovies"] as? [String] else {
                return nil
        }
        return User(
            firstName: firstName,
            lastName: lastName,
            isCurrent: isCurrent,
            favouriteMovies: favouriteMovieUuids)
    }

    func setUp(transaction: ReadWriteTransaction) throws {
        try transaction.registerCollection(self)
        try transaction.registerExtension(index)
    }

    struct IndexedProperties: Turf.IndexedProperties {
        let isCurrent = IndexedProperty<UsersCollection, Bool>(name: "isCurrent") { user in
            return user.isCurrent
        }

        var allProperties: [IndexedPropertyFromCollection<UsersCollection>] {
            return [isCurrent.lift()]
        }
    }
}

final class Collections: CollectionsContainer {
    let users = UsersCollection()
    let movies = MoviesCollection()

    func setUpCollections(transaction transaction: ReadWriteTransaction) throws {
        try users.setUp(transaction)
//: Set up the new collection.
        try movies.setUp(transaction)
    }
}

//: Usual set up

let collections = Collections()
let database = try! Database(path: "AdvancedObservables.sqlite", collections: collections)
let connection = try! database.newConnection()
let observingConnection = try! database.newObservingConnection()


//: When the current user changes we want to keep an up to date list of their favourite movies.
let observableCurrentUserCurrentUsersFavouriteMovies = CollectionTypeObserver<[Movie]>(initalValue: [])

let observableUsersCollection = observingConnection.observeCollection(collections.users)

//: Lets utilise our secondary index to fetch the current user when the database changes.
//: Our `valuesWhere` query will run every time the users collection changes. See <PerformanceEnhancements> for optimisations.
//: `currentUser` will always represent the first value returned from the query - the current user!
let observableCurrentUser =
    observableUsersCollection
    .valuesWhere(collections.users.indexed.isCurrent.equals(true))
    .first

observableCurrentUser.didChange { (currentUser, transaction) in
    guard let currentUser = currentUser, readTransaction = transaction else {
//: When there is no current user, set the movies collection to empty.
        observableCurrentUserCurrentUsersFavouriteMovies.setValue([], fromTransaction: transaction)
        return
    }

    let moviesCollection = readTransaction.readOnly(collections.movies)
//: Fetch all movies the current user likes.
    let movies = currentUser.favouriteMovies.flatMap { uuid in
        return moviesCollection.valueForKey(uuid)
    }
//: Set the observable list to the movies we fetched.
    observableCurrentUserCurrentUsersFavouriteMovies.setValue(movies, fromTransaction: readTransaction)
}

//: Lets add some movies first - this shouldn't trigger any updates!
try! connection.readWriteTransaction { (transaction) in
    let moviesCollection = transaction.readWrite(collections.movies)

    let movies = [
        Movie(uuid: "1", name: "Ghostbusters"),
        Movie(uuid: "2", name: "Saving Private Ryan"),
        Movie(uuid: "3", name: "Cast Away"),
        Movie(uuid: "4", name: "American Hustle"),
        Movie(uuid: "5", name: "Man of Steel")
    ]

    for movie in movies {
        moviesCollection.setValue(movie, forKey: movie.uuid)
    }
}

//: Lets add our users - this should trigger the observables.
try! connection.readWriteTransaction { (transaction) in
    let usersCollection = transaction.readWrite(collections.users)

    let bill = User(
        firstName: "Bill",
        lastName: "Murray",
        isCurrent: false,
        favouriteMovies: ["1", "4"])

    let tom = User(
        firstName: "Tom",
        lastName: "Hanks",
        isCurrent: false,
        favouriteMovies: ["2", "3", "4"])

    let amy = User(
        firstName: "Amy",
        lastName: "Adams",
        isCurrent: true,
        favouriteMovies: ["1", "2", "4", "5"])


    usersCollection.setValue(amy, forKey: "AmyAdams")
    usersCollection.setValue(bill, forKey: "BillMurray")
    usersCollection.setValue(tom, forKey: "TomHanks")

}

observableCurrentUser.value
observableCurrentUserCurrentUsersFavouriteMovies.value
