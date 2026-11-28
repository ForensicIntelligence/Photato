import AppKit
import PhotoCraftImaging

enum RawFilmstripLabel: String, CaseIterable {
  case none = "No Label"
  case red = "Red"
  case yellow = "Yellow"
  case green = "Green"
  case blue = "Blue"
  case purple = "Purple"
  case other = "Other Labels"

  init(marking: RawPhotoMarking) {
    guard let name = marking.label, !name.isEmpty else { self = .none; return }
    self = Self.allCases.dropFirst().dropLast().first { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame } ?? .other
  }
}

enum RawFilmstripOrder: String, CaseIterable {
  case opening = "Opening Order"
  case name = "File Name"
  case captureDate = "Capture Date"
  case fileType = "File Type"
  case camera = "Camera"
  case lens = "Lens"
  case rating = "Star Rating"
  case label = "Color Label"
}

enum RawFilmstripRatingFilter: String, CaseIterable {
  case all = "All Ratings"
  case unrated = "Unrated"
  case rejected = "Rejected"
  case one = "1 Star or More"
  case two = "2 Stars or More"
  case three = "3 Stars or More"
  case four = "4 Stars or More"
  case five = "5 Stars"

  func includes(_ rating: Int?) -> Bool {
    let value = rating ?? 0
    switch self {
    case .all: return true
    case .unrated: return value == 0
    case .rejected: return value == -1
    case .one: return value >= 1
    case .two: return value >= 2
    case .three: return value >= 3
    case .four: return value >= 4
    case .five: return value == 5
    }
  }
}

@MainActor extension RawFilmstripWorkspace {
  /// Avoid consuming typed digits and punctuation while editing an adjustment field.
  func handleMarkingKey(_ event: NSEvent) -> Bool {
    guard !busy, !closed, let key = event.charactersIgnoringModifiers,
      !(event.window?.firstResponder is NSTextView) else { return false }
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    switch (flags, key) {
    case ([], "0"), ([], "1"), ([], "2"), ([], "3"), ([], "4"), ([], "5"):
      if let rating = Int(key) { setRating(rating) }
    case ([], "6"): setLabel(.red)
    case ([], "7"): setLabel(.yellow)
    case ([], "8"): setLabel(.green)
    case ([], "9"): setLabel(.blue)
    case ([.command, .shift], "0"), ([.command, .shift], ")"): setLabel(.purple)
    case (.command, ","): changeRating(-1)
    case (.command, "."): changeRating(1)
    case ([.command, .option], "a"): selectRated()
    default: return false
    }
    return true
  }
}
