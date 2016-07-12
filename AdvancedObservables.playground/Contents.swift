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

let observableUsersCollection = observingConnection.observeCollection(collections.users)

//: Lets utilise our secondary index to fetch the current user when the database changes.
//: Our `values(matching:)` query will run every time the users collection changes. See <PerformanceEnhancements> for optimisations.
//: We map the returned users to a single user + read transaction pair (`TransactionalValue`)
//: so we can use the same transaction in a following subscriber.
let observableCurrentUser =
    observableUsersCollection
        .values(matching: collections.users.indexed.isCurrent.equals(true))
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
                return moviesCollection.valueForKey(uuid)
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
        moviesCollection.setValue(movie, forKey: movie.uuid)
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


    usersCollection.setValue(amy, forKey: "AmyAdams")
    usersCollection.setValue(bill, forKey: "BillMurray")
    usersCollection.setValue(tom, forKey: "TomHanks")
}

let currentUserDisposable = observableCurrentUser.subscribeNext { currentUserTransaction in
    print(currentUserTransaction.value)
}

let moviesDisposable = observableCurrentUsersFavouriteMovies.subscribeNext { currentUsersMovies in
    print(currentUsersMovies)
}
