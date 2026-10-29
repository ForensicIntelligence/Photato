import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

@MainActor final class NewDocumentOptions: NSStackView {
  let widthField = NSTextField(string: "1200")
  let heightField = NSTextField(string: "800")
  let resolutionField = NSTextField(string: "72")
  let modeMenu = NSPopUpButton()
  let depthMenu = NSPopUpButton()
  let backgroundMenu = NSPopUpButton()
  let profileLabel = NSTextField(labelWithString: "System default profile")
  private(set) var profile: Data?
  let settings: ColorSettings
  var mode: DocumentColorMode { DocumentColorMode.componentModes[modeMenu.indexOfSelectedItem] }
  var depth: PixelDepth { PixelDepth.allCases[depthMenu.indexOfSelectedItem] }

  init(settings: ColorSettings = .init()) {
    self.settings = settings
    super.init(frame: NSRect(x: 0, y: 0, width: 316, height: 421))
    orientation = .vertical; alignment = .leading; spacing = 6
    edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    modeMenu.addItems(withTitles: DocumentColorMode.componentModes.map(\.title))
    depthMenu.addItems(withTitles: ["8 bit", "16 bit", "32 bit (float)"])
    depthMenu.menu?.autoenablesItems = false
    backgroundMenu.addItems(withTitles: ["White", "Transparent", "Background Color"])
    modeMenu.target = self; modeMenu.action = #selector(modeChanged)
    depthMenu.target = self; depthMenu.action = #selector(depthChanged)
    for (label, view) in [
      ("Width (pixels)", widthField), ("Height (pixels)", heightField),
      ("Resolution (pixels/inch)", resolutionField), ("Color Mode", modeMenu),
      ("Bit Depth", depthMenu), ("Background Contents", backgroundMenu),
    ] as [(String, NSView)] {
      addArrangedSubview(NSTextField(labelWithString: label)); addArrangedSubview(view)
      view.widthAnchor.constraint(equalToConstant: 300).isActive = true
    }
    profileLabel.lineBreakMode = .byTruncatingMiddle
    profileLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
    addArrangedSubview(profileLabel)
    let choose = NSButton(title: "Choose ICC Profile…", target: self, action: #selector(chooseProfile))
    let reset = NSButton(title: "Reset", target: self, action: #selector(resetProfile))
    let buttons = NSStackView(views: [choose, reset]); buttons.spacing = 8
    addArrangedSubview(buttons)
    resetProfile()
  }
  required init?(coder: NSCoder) { nil }

  @objc func modeChanged() {
    depthMenu.item(at: 2)?.isEnabled = mode.depths.contains(.f32)
    if !mode.depths.contains(depth) { depthMenu.selectItem(at: 1) }
    resetProfile()
  }
  @objc func depthChanged() { resetProfile() }
  @objc func resetProfile() {
    profile = nil
    let space = (try? settings.profile(mode, depth: depth)).flatMap { CGColorSpace(iccData: $0 as CFData) }
    profileLabel.stringValue = "Working: " + (space.flatMap { NSColorSpace(cgColorSpace: $0)?.localizedName } ?? mode.title) + (settings.policy(mode) == .off ? " (untagged)" : "")
  }
  func setProfile(_ data: Data, name: String) throws {
    try NativeModeProfile.validate(data, mode: mode, depth: depth)
    profile = data; profileLabel.stringValue = name
  }
  @objc private func chooseProfile() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType(filenameExtension: "icc"), UTType(filenameExtension: "icm")].compactMap { $0 }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
      guard size <= ICCProfile.maximumBytes else { throw CraftError.invalid("ICC profiles are limited to 4 MiB.") }
      try setProfile(Data(contentsOf: url), name: url.lastPathComponent)
    } catch { NSApp.presentError(error) }
  }
  func document(name: String, background: Pixel = .white) throws -> CraftDocument {
    guard let width = Int(widthField.stringValue), let height = Int(heightField.stringValue),
      let resolution = Double(resolutionField.stringValue) else {
      throw CraftError.invalid("Enter whole-number dimensions and a valid resolution.")
    }
    let fill: Pixel = backgroundMenu.indexOfSelectedItem == 1 ? .clear
      : backgroundMenu.indexOfSelectedItem == 2 ? background : .white
    var result = try CraftNSDocument.blankModel(width: width, height: height, depth: depth,
      background: fill, name: name, mode: mode, profile: profile ?? settings.profile(mode, depth: depth), resolution: resolution)
    if profile == nil, settings.policy(mode) == .off { result.profileIsUntagged = true }
    return result
  }
}
