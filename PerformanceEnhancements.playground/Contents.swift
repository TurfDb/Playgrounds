//: ## Performance Enhancements
//: Here we are going to investigate a `Collection`'s `valueCacheSize` and how to create a prepared query. We're keeping the setup almost identical to <AdvancedObservables> and just going to focus on performance.
import Turf


struct Movie {
    let uuid: String
    let name: String
}

struct User {
    let firstName: String
    let lastName: String
    let isCurrent: Bool
    let favouriteMovies: [String]

    var key: String { return "\(firstName)\(lastName)" }
}

final class MoviesCollection: Collection {
    typealias Value = Movie

    let name = "Movies"
    let schemaVersion = UInt64(1)

//: Turf gains a lot of performance by caching deserialized objects on each connection. If you set a value then read it out on the same connection, we will read out a cached version without performing any deserialization.

//: Each `Connection` has its own cache and each `Collection` within that connection has it's own cache. The default `Collection` cache size is 50 objects. Beyond this cache size, the least recently used objects will begin to get evicted, affecting the performance if they are read out again.

//: For example, if we were reading out many more `Movie`s than `User`s, we explicitly set the `MoviesCollection`'s cache size here. This will allow us to read 150 distinct `Movie`s on a connection without evicting anything from the cache and suffering a future performance hit.

//: Because the caches are per connection per collection it is a good idea to reuse a `Connection` as often as possible - a common set up is 1 connection for reads, 1 connection for read-writes and 1 connection for observing.

//: Having a separate connection for only reading is useful because reads do not block across mutliple connections. Multiple `readTransaction`s can occurr simultaneously where as a `readWriteTransaction` does stop all other connections from writing for thread safety.
    let valueCacheSize: Int? = 150

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

    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
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

    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
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

    func setUpCollections<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try users.setUp(using: transaction)
        try movies.setUp(using: transaction)
    }
}

let collections = Collections()
let database = try! Database(path: "AdvancedObservables.sqlite", collections: collections)
let connection = try! database.newConnection()
let observingConnection = try! database.newObservingConnection()


let observableCurrentUserCurrentUsersFavouriteMovies = CollectionTypeObserver<[Movie], Collections>(initalValue: [])

//: Lets say in our app, the users collection is written to a lot, this will trigger our query to be run many, many times. The first way to improve this performance is to use a "Prepared Query". This reduces the overhead of not having to set up the query each time it is run.
let currentUserQuery = try! observingConnection
    .prepareQueryFor(collections.users, valuesWhere: collections.users.indexed.isCurrent.equals(true))
//: **Note:** Turf currently doesn't support prepared queries with placeholder values that can get repopulated at the time of query.

//: We're still going to run our (potentially) expensive query each time the users collection is written to. 

//: In our case, we only want to query for a new current user iff the current user's `isCurrent` field is set to false. By prefiltering the collection's change set to see if the existing current user's key has a change, we don't have to run the query every time.

let observableCurrentUser =
    observingConnection.observeCollection(collections.users)
        .valuesWhere(currentUserQuery, thread: .CallingThread,
                     prefilterChangeSet: { (previousValues, changeSet) -> Bool in
                        guard let currentUserBeforeChangeSet = previousValues.first else { return true }
                        return changeSet.hasChangeForKey(currentUserBeforeChangeSet.key)
                     }
        )
        .first

observableCurrentUser.didChange { (currentUser, transaction) in
    guard let currentUser = currentUser, readTransaction = transaction else {
        observableCurrentUserCurrentUsersFavouriteMovies.setValue([], fromTransaction: transaction)
        return
    }

    let moviesCollection = readTransaction.readOnly(collections.movies)
    let movies = currentUser.favouriteMovies.flatMap { uuid in
        return moviesCollection.valueForKey(uuid)
    }
    observableCurrentUserCurrentUsersFavouriteMovies.setValue(movies, fromTransaction: readTransaction)
}

try! connection.readWriteTransaction { transaction, collections in
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

try! connection.readWriteTransaction { transaction, collections in
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


    usersCollection.setValue(amy, forKey: amy.key)
    usersCollection.setValue(bill, forKey: bill.key)
    usersCollection.setValue(tom, forKey: tom.key)
    
}

observableCurrentUser.value
observableCurrentUserCurrentUsersFavouriteMovies.value
