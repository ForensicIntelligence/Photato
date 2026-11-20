import Foundation
import Observation
import PhotoCraftImaging

@MainActor @Observable final class PrintPreferences {
  static let key = "Photato.LastAcceptedPrint.v1"
  private let defaults: UserDefaults?
  private(set) var settings = PrintSettings()
  private(set) var revision = UUID()

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
    if let data = defaults?.data(forKey: Self.key),
      var decoded = try? JSONDecoder().decode(PrintSettings.self, from: data),
      (try? decoded.validate()) != nil {
      decoded.selectedArea = false
      settings = decoded
    }
  }

  func remember(_ accepted: PrintSettings) throws {
    var settings = accepted
    settings.selectedArea = false
    try settings.validate()
    guard settings != self.settings else { return }
    let data = try JSONEncoder().encode(settings)
    defaults?.set(data, forKey: Self.key)
    self.settings = settings
    revision = UUID()
  }
}
