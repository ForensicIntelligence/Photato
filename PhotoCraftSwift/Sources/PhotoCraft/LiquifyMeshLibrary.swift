import Foundation
import Observation
import PhotoCraftCore

/// Only a committed Liquify program is retained; drafts and source pixels never enter this file.
@MainActor @Observable final class LiquifyMeshLibrary {
  static let shared = LiquifyMeshLibrary(persistenceURL: FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask).first?
    .appendingPathComponent("Photato/LiquifyLastMesh.photatoliquify"))

  private(set) var settings: LiquifySettings?
  private(set) var error: String?
  private(set) var revision = UUID()
  @ObservationIgnored let persistenceURL: URL?
  @ObservationIgnored private let writes = DispatchQueue(label: "ca.forensicintelligence.photato.liquify-mesh")
  @ObservationIgnored private var preserveUnreadableFile = false
  @ObservationIgnored private var generation = 0

  init(persistenceURL: URL? = nil, initialSettings: LiquifySettings? = nil) {
    self.persistenceURL = persistenceURL
    if let initialSettings {
      do { _ = try LiquifyMeshFile.encode(initialSettings); settings = initialSettings }
      catch { self.error = "The previous Liquify mesh is invalid." }
    }
    guard let url = persistenceURL, FileManager.default.fileExists(atPath: url.path) else { return }
    do {
      let file = try FileHandle(forReadingFrom: url)
      defer { try? file.close() }
      settings = try LiquifyMeshFile.decode(file.read(upToCount: LiquifyMeshFile.maximumBytes + 1) ?? Data())
    } catch {
      preserveUnreadableFile = true
      self.error = "The saved Liquify mesh could not be read. Its file has been preserved; new meshes remain available for this session."
    }
  }

  func remember(_ value: LiquifySettings) {
    let data: Data
    do { data = try LiquifyMeshFile.encode(value) }
    catch {
      generation += 1
      self.error = "The last Liquify mesh could not be retained. The image edit is still applied."
      revision = UUID()
      return
    }
    guard settings != value || (error != nil && !preserveUnreadableFile) else { return }
    settings = value
    generation += 1
    revision = UUID()
    guard !preserveUnreadableFile else { return }
    error = nil
    guard let url = persistenceURL else { return }
    let accepted = generation
    writes.async { [weak self] in
      let failed: Bool
      do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        failed = false
      } catch { failed = true }
      Task { @MainActor [weak self] in
        guard let self, self.generation == accepted else { return }
        let notice = failed ? "The last Liquify mesh is available for this session but could not be saved." : nil
        if self.error != notice { self.error = notice; self.revision = UUID() }
      }
    }
  }

  /// Drain accepted atomic writes before normal application termination.
  func flush() { writes.sync {} }

  func detachedCopy() -> LiquifyMeshLibrary { .init(initialSettings: settings) }
}
