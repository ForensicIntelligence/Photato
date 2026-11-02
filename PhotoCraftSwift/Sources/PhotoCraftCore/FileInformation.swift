import Foundation

/// Descriptive File Info fields. Unedited XMP properties remain in sourceMetadata.
public struct FileInformation: Codable, Equatable, Sendable {
  public enum CopyrightStatus: String, CaseIterable, Codable, Sendable {
    case unknown, copyrighted, publicDomain
  }
  public static let fields = ["title", "author", "authorTitle", "description", "keywords", "copyright", "copyrightStatus", "copyrightUrl"]
  public static let maximumTextBytes = 65_536
  public static let maximumKeywords = 256
  public var title = ""
  public var author = ""
  public var authorTitle = ""
  public var description = ""
  public var keywords: [String] = []
  public var copyright = ""
  public var copyrightStatus: CopyrightStatus = .unknown
  public var copyrightUrl = ""
  public init() {}
  public func validate() throws {
    let values = [title, author, authorTitle, description, copyright, copyrightUrl] + keywords
    guard keywords.count <= Self.maximumKeywords,
      values.allSatisfy({ $0.utf8.count <= Self.maximumTextBytes && !$0.contains("\0") }),
      values.reduce(0, { $0 + $1.utf8.count }) <= 1_048_576 else {
      throw CraftError.invalid("File Info exceeds its text or keyword limit, or contains null characters.")
    }
  }
  public func changedFields(from original: Self) -> Set<String> {
    var result: Set<String> = []
    for (key, changed) in [("title", title != original.title), ("author", author != original.author),
      ("authorTitle", authorTitle != original.authorTitle), ("description", description != original.description),
      ("keywords", keywords != original.keywords), ("copyright", copyright != original.copyright),
      ("copyrightStatus", copyrightStatus != original.copyrightStatus), ("copyrightUrl", copyrightUrl != original.copyrightUrl)] where changed {
      result.insert(key)
    }
    return result
  }
}
