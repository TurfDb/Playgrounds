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
final class MoviesCollection: TurfCollection {
    typealias Value = Movie

    let name = "Movies"
    let schemaVersion = UInt64(1)
    let valueCacheSize: Int? = nil

    func serialize(value: Movie) -> Data {
        let dictionaryRepresentation: [String: Any] = [
            "uuid": value.uuid,
            "name": value.name
        ]

        return try! JSONSerialization.data(withJSONObject: dictionaryRepresentation, options: [])
    }

    func deserialize(data: Data) -> Movie? {
        let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        guard
            let uuid = json["uuid"] as? String,
            let name = json["name"] as? String else {
                return nil
        }
        return Movie(
            uuid: uuid,
            name: name)
    }

    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try transaction.register(collection: self)
    }
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
        let dictionaryRepresentation: [String: Any] = [
            "firstName": value.firstName,
            "lastName": value.lastName,
            "isCurrent": value.isCurrent,
            "favouriteMovies": value.favouriteMovies
        ]

        return try! JSONSerialization.data(withJSONObject: dictionaryRepresentation, options: [])
    }

    func deserialize(data: Data) -> User? {
        let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        guard
            let firstName = json["firstName"] as? String,
            let lastName = json["lastName"] as? String,
            let isCurrent = json["isCurrent"] as? Bool,
            let favouriteMovieUuids = json["favouriteMovies"] as? [String] else {
                return nil
        }
        return User(
            firstName: firstName,
            lastName: lastName,
            isCurrent: isCurrent,
            favouriteMovies: favouriteMovieUuids)
    }

    func setUp<Collections: CollectionsContainer>(using transaction: ReadWriteTransaction<Collections>) throws {
        try transaction.register(collection: self)
        try transaction.register(extension: index)
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
//: Set up the new collection.
        try movies.setUp(using: transaction)
    }
}

//: Usual set up

let collections = Collections()
let database = try! Database(path: "AdvancedObservables.sqlite", collections: collections)
let connection = try! database.newConnection()
let observingConnection = try! database.newObservingConnection()


//: When the current user changes we want to keep an up to date list of their favourite movies.

let observableUsersCollection = observingConnection.observe(collection: collections.users)

//: Lets utilise our secondary index to fetch the current user when the database changes.
//: Our `values(matching:)` query will run every time the users collection changes. See <PerformanceEnhancements> for optimisations.
//: We map the returned users to a single user + read transaction pair (`TransactionalValue`)
//: so we can use the same transaction in a following subscriber.
let observableCurrentUser =
    observableUsersCollection
        .values(where: collections.users.indexed.isCurrent.equals(true))
        .map { transactionalUsers -> TransactionalValue<User?, Collections> in

            let transactionalCurrentUser = transactionalUsers.map { users -> User? in
                return users.first
            }
            return transactionalCurrentUser
        }
//: `share()` creates a multicasting observable - many observers can subscribe to the one observable.
//: The shared observable will not be disposed until all observers are disposed.
//: We use share here so that the `map` on line 165 and the `subscribeNext` on line 226 use the same
//: underlying observable instead of a new one for the `map` and a new one for the `subscribeNext`.
//: `shareReplay()` is the same as `share()` but will replay the previous values on new subscriptions.
        .shareReplay(bufferSize: 1)


let observableCurrentUsersFavouriteMovies =
    observableCurrentUser
        .map { transactionalCurrentUser -> [Movie] in
//: If there is no current user, return an empty array
            guard let currentUser = transactionalCurrentUser.value else {
                return []
            }

//: Now we can use the same transaction the user was fetched on to fetch all the movies the user likes
            let moviesCollection = transactionalCurrentUser.transaction.readOnly(collections.movies)
            let movies = currentUser.favouriteMovies.flatMap { uuid in
                return moviesCollection.value(for: uuid)
            }

            return movies
        }

//: Lets add some movies first - this shouldn't trigger any updates!
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
        moviesCollection.set(value: movie, forKey: movie.uuid)
    }
}

//: Lets add our users - this should trigger the observables.
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


    usersCollection.set(value: amy, forKey: "AmyAdams")
    usersCollection.set(value: bill, forKey: "BillMurray")
    usersCollection.set(value: tom, forKey: "TomHanks")
}

let currentUserDisposable = observableCurrentUser.subscribeNext { currentUserTransaction in
    print(currentUserTransaction.value)
}

let moviesDisposable = observableCurrentUsersFavouriteMovies.subscribeNext { currentUsersMovies in
    print(currentUsersMovies)
}
