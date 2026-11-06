import Foundation
import Observation
import PhotoCraftCore

struct WorkspaceLayout: Codable, Equatable {
  var visibility = WorkspaceVisibility()
  var colorTab = ColorPanelTab.color
  var propertiesTab = PropertiesTab.properties
  var layersTab = LayersTab.layers
  var dockWidth: Double = 322
  var propertiesHeight: Double = 360
  var doubleTools = false
  var panelDock: PanelDock?

  func validate() throws {
    guard dockWidth.isFinite, (275...410).contains(dockWidth),
      propertiesHeight.isFinite, (160...10000).contains(propertiesHeight)
    else { throw CraftError.invalid("Invalid workspace panel dimensions.") }
    try panelDock?.validate()
  }
}

struct SavedWorkspace: Codable, Equatable {
  var name: String
  var saved: WorkspaceLayout
  var lastUsed: WorkspaceLayout
}

struct WorkspaceState: Codable, Equatable {
  var version = 1
  var layerPanelOptions: LayerPanelOptions?
  var channelPanelOptions: ChannelPanelOptions?
  var workspaceLocked: Bool?
  var active = "Essentials"
  var workspaces = [SavedWorkspace(name: "Essentials", saved: .init(), lastUsed: .init())]

  static let reservedNames = [
    "Essentials", "Essentials (Default)", "Motion", "Painting", "Photography", "Graphic and Web",
    "Pixel Art",
  ]
  static let maximumCount = 128
  static let maximumBytes = 2 * 1024 * 1024

  static func normalizedName(_ name: String) throws -> String {
    let result = name.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
    guard !result.isEmpty, result.utf8.count <= 256,
      !result.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw CraftError.invalid(
        "That workspace name is empty, too long, or contains control characters.")
    }
    return result
  }

  static func sameName(_ first: String, _ second: String) -> Bool {
    first.compare(second, options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      == .orderedSame
  }

  func validate() throws {
    guard version == 1, !workspaces.isEmpty, workspaces.count <= Self.maximumCount,
      workspaces.first?.name == "Essentials", workspaces.first?.saved == WorkspaceLayout(),
      workspaces.contains(where: { $0.name == active })
    else { throw CraftError.invalid("Invalid or unsupported workspace file.") }
    var names: [String] = []
    for workspace in workspaces {
      guard try Self.normalizedName(workspace.name) == workspace.name,
        !names.contains(where: { Self.sameName($0, workspace.name) }),
        workspace.name == "Essentials"
          || !Self.reservedNames.contains(where: { Self.sameName($0, workspace.name) })
      else { throw CraftError.invalid("Invalid or duplicate workspace name.") }
      try workspace.saved.validate()
      try workspace.lastUsed.validate()
      names.append(workspace.name)
    }
  }
}

/// Shared application presentation. Never included in an image document or its undo history.
@MainActor @Observable final class WorkspaceLibrary {
  @ObservationIgnored let identity = UUID()
  static let shared = WorkspaceLibrary(
    persistenceURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first?.appendingPathComponent("Photato/Workspaces.json"))

  private(set) var state = WorkspaceState()
  private(set) var panelRevision = UUID()
  var error: String?
  var expandedDockColumnID: String?
  @ObservationIgnored let persistenceURL: URL?
  @ObservationIgnored private var loadFailed = false
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private let writeData: (Data, URL) throws -> Void

  init(persistenceURL: URL? = nil, writer: ((Data, URL) throws -> Void)? = nil) {
    self.persistenceURL = persistenceURL
    writeData =
      writer ?? { data, url in
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
      }
    if let url = persistenceURL, FileManager.default.fileExists(atPath: url.path) {
      do {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= WorkspaceState.maximumBytes else {
          throw CraftError.invalid("Workspace file is too large.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= WorkspaceState.maximumBytes else {
          throw CraftError.invalid("Workspace file is too large.")
        }
        let loaded = try JSONDecoder().decode(WorkspaceState.self, from: data)
        try loaded.validate()
        state = loaded
      } catch {
        loadFailed = true
        self.error =
          "Could not load saved workspaces. The original file has been preserved. \(error.localizedDescription)"
      }
    }
  }

  var activeName: String { state.active }
  var customNames: [String] { state.workspaces.dropFirst().map(\.name) }
  var deletableNames: [String] { customNames.filter { $0 != activeName } }
  private var activeIndex: Int { state.workspaces.firstIndex { $0.name == state.active }! }
  var layout: WorkspaceLayout {
    get { state.workspaces[activeIndex].lastUsed }
    set {
      guard newValue != layout else { return }
      do { try newValue.validate() } catch {
        self.error = error.localizedDescription
        return
      }
      state.workspaces[activeIndex].lastUsed = newValue
      panelRevision = UUID()
      saveTask?.cancel()
      guard persistenceURL != nil else { return }
      saveTask = Task { [weak self] in
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        try? self?.flush()
      }
    }
  }

  func setPanelLayout(_ value: WorkspaceLayout) throws {
    try value.validate()
    guard value != layout else { return }
    var canonical = layout
    if canonical.panelDock == nil { canonical.panelDock = panelDock }
    guard value != canonical else { return }
    var next = state
    next.workspaces[activeIndex].lastUsed = value
    try commit(next)
  }

  func setPanelVisible(_ panel: WorkspacePanel, _ visible: Bool) throws {
    let draft = WorkspaceLibrary()
    draft.layout = layout
    if visible { draft.selectPanel(panel, reveal: true) }
    else { draft.closePanels([panel]) }
    try setPanelLayout(draft.layout)
    if visible { expandedDockColumnID = draft.expandedDockColumnID }
  }

  func resizeDock(to width: Double) {
    guard width.isFinite else { return }
    layout.dockWidth = min(410, max(275, width))
  }

  func setWorkspaceLocked(_ locked: Bool) throws {
    var next = state
    next.workspaceLocked = locked
    try commit(next)
  }

  func resizeProperties(to height: Double) {
    guard height.isFinite else { return }
    layout.propertiesHeight = min(10000, max(160, height))
  }

  var layerPanelOptions: LayerPanelOptions { state.layerPanelOptions ?? LayerPanelOptions() }

  func setLayerPanelOptions(_ options: LayerPanelOptions) throws {
    guard options != layerPanelOptions else { return }
    var next = state
    next.layerPanelOptions = options
    try commit(next)
  }

  var channelPanelOptions: ChannelPanelOptions {
    state.channelPanelOptions ?? ChannelPanelOptions()
  }

  func setChannelPanelOptions(_ options: ChannelPanelOptions) throws {
    guard options != channelPanelOptions else { return }
    var next = state
    next.channelPanelOptions = options
    try commit(next)
  }

  func save(name: String, replacing: Bool = false) throws {
    let name = try WorkspaceState.normalizedName(name)
    guard !WorkspaceState.reservedNames.contains(where: { WorkspaceState.sameName($0, name) })
    else { throw CraftError.invalid("That name belongs to a built-in workspace.") }
    var next = state
    if let index = next.workspaces.firstIndex(where: { WorkspaceState.sameName($0.name, name) }) {
      guard replacing else {
        throw CraftError.invalid("A workspace with that name already exists.")
      }
      next.workspaces[index] = SavedWorkspace(name: name, saved: layout, lastUsed: layout)
    } else {
      guard next.workspaces.count < WorkspaceState.maximumCount else {
        throw CraftError.invalid("The workspace list is full.")
      }
      next.workspaces.append(SavedWorkspace(name: name, saved: layout, lastUsed: layout))
    }
    next.active = name
    try commit(next)
  }

  func select(_ name: String) throws {
    guard state.workspaces.contains(where: { $0.name == name }) else {
      throw CraftError.invalid("Workspace not found.")
    }
    var next = state
    next.active = name
    try commit(next)
  }

  func reset() throws {
    var next = state
    next.workspaces[activeIndex].lastUsed = next.workspaces[activeIndex].saved
    try commit(next)
  }

  func delete(_ name: String) throws {
    guard deletableNames.contains(name) else {
      throw CraftError.invalid("Switch to another workspace before deleting this custom workspace.")
    }
    var next = state
    next.workspaces.removeAll { $0.name == name }
    try commit(next)
  }

  func flush() throws {
    saveTask?.cancel()
    saveTask = nil
    do { try persist(state) } catch {
      self.error = error.localizedDescription
      throw error
    }
  }

  private func commit(_ next: WorkspaceState) throws {
    try persist(next)
    saveTask?.cancel()
    saveTask = nil
    if state != next { panelRevision = UUID() }
    state = next
  }

  private func persist(_ next: WorkspaceState) throws {
    guard !loadFailed else {
      throw CraftError.invalid(
        "The saved workspace file could not be read and has been preserved. Repair it before saving workspace changes."
      )
    }
    try next.validate()
    guard let url = persistenceURL else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(next)
    guard data.count <= WorkspaceState.maximumBytes else {
      throw CraftError.invalid("Workspace file is too large.")
    }
    try writeData(data, url)
  }
}
