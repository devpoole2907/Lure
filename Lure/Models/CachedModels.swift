import Foundation
import SwiftData

@Model
final class CachedLibraryItem {
    @Attribute(.unique) var id: String
    var serverURL: String
    var tmdbId: Int
    var mediaType: String
    var title: String
    var year: String?
    var voteAverage: Double?
    var posterURLString: String?
    var isAvailable: Bool
    var addedAt: Date?

    init(serverURL: String, item: LibraryItem) {
        self.id = "\(serverURL)-\(item.mediaType)-\(item.tmdbId)"
        self.serverURL = serverURL
        self.tmdbId = item.tmdbId
        self.mediaType = item.mediaType
        self.title = item.title
        self.year = item.year
        self.voteAverage = item.voteAverage
        self.posterURLString = item.posterURL?.absoluteString
        self.isAvailable = item.isAvailable
        self.addedAt = item.addedAt
    }

    var toLibraryItem: LibraryItem {
        LibraryItem(
            mediaType: mediaType,
            tmdbId: tmdbId,
            title: title,
            year: year,
            voteAverage: voteAverage,
            posterURL: posterURLString.flatMap { URL(string: $0) },
            isAvailable: isAvailable,
            addedAt: addedAt
        )
    }
}

@Model
final class CachedRequestItem {
    @Attribute(.unique) var id: String
    var serverURL: String
    var requestId: Int
    var requestData: Data

    init(serverURL: String, requestId: Int, requestData: Data) {
        self.id = "\(serverURL)-\(requestId)"
        self.serverURL = serverURL
        self.requestId = requestId
        self.requestData = requestData
    }

    var toRequest: SeerrMediaRequest? {
        try? JSONDecoder().decode(SeerrMediaRequest.self, from: requestData)
    }
}
