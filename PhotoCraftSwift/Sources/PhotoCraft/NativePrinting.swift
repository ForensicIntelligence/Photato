import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class PrintPageView: NSView {
  let output: PreparedPrint
  var previewPage: Int?
  init(_ output: PreparedPrint, previewPage: Int? = nil) {
    self.output = output; self.previewPage = previewPage
    super.init(frame: output.layout.page)
  }
  required init?(coder: NSCoder) { nil }
  override func knowsPageRange(_ range: NSRangePointer) -> Bool { range.pointee = NSRange(location: 1, length: output.pages.count); return true }
  override func rectForPage(_ page: Int) -> NSRect { output.layout.page }
  override func locationOfPrintRect(_ rect: NSRect) -> NSPoint { .zero }
  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState(); defer { context.restoreGState() }
    if previewPage != nil {
      let scale = min(bounds.width / output.layout.page.width, bounds.height / output.layout.page.height)
      context.translateBy(x: (bounds.width - output.layout.page.width * scale) / 2, y: (bounds.height - output.layout.page.height * scale) / 2)
      context.scaleBy(x: scale, y: scale)
      context.setFillColor(gray: 1, alpha: 1); context.fill(output.layout.page)
    }
    output.draw(page: previewPage ?? max(0, (NSPrintOperation.current?.currentPage ?? 1) - 1), in: context)
  }
}
@MainActor final class NativePrintJob: NSObject {
  private var operation: NSPrintOperation?
  private var completion: ((Bool) -> Void)?
  func run(_ output: PreparedPrint, info: NSPrintInfo, window: NSWindow, completion: @escaping (Bool) -> Void) {
    let operation = NSPrintOperation(view: PrintPageView(output), printInfo: info)
    operation.jobTitle = output.title; operation.showsPrintPanel = false; operation.showsProgressPanel = true
    self.operation = operation; self.completion = completion
    operation.runModal(for: window, delegate: self, didRun: #selector(finished(_:success:context:)), contextInfo: nil)
  }
  @objc private func finished(_ operation: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) {
    let callback = completion; completion = nil; self.operation = nil; callback?(success)
  }
}

extension EditorStore {
  var canBeginPrint: Bool { canBeginDocumentMode && !printBusy }
  func setPrintSettings(_ settings: PrintSettings) throws {
    _ = try PrintLayout(document: document, settings: settings)
    guard settings != printSettings else { return }
    printSettings = settings; printRevision = UUID()
  }
  func finishPrintSheet() { let action = printAfterDismiss; printAfterDismiss = nil; action?() }
}
extension CraftNSDocument {
  var canBeginPrint: Bool { canRunFileCommand && closeWorkflowID == nil && store.canBeginPrint }
  func beginPrint() {
    guard canBeginPrint else { return }
    let draft = PrintWorkspace(self); store.printWorkspace = draft; draft.refresh()
  }
  /// An independent copy prevents cancelled driver/page panels from changing remembered state.
  func info(for settings: PrintSettings, base: NSPrintInfo? = nil) throws -> NSPrintInfo {
    try settings.validate()
    let info = (base ?? rememberedPrintInfo ?? printInfo).copy() as! NSPrintInfo
    if !settings.printerName.isEmpty {
      guard let printer = NSPrinter(name: settings.printerName) else { throw CraftError.invalid("The selected printer is no longer available.") }
      info.printer = printer
    }
    info.orientation = .portrait
    info.paperSize = settings.paper == .custom ? CGSize(width: settings.customWidth, height: settings.customHeight) : settings.paper.size
    info.orientation = settings.orientation == .landscape ? .landscape : .portrait
    info.leftMargin = 0; info.rightMargin = 0; info.topMargin = 0; info.bottomMargin = 0
    info.isHorizontallyCentered = false; info.isVerticallyCentered = false
    info.horizontalPagination = .clip; info.verticalPagination = .clip; info.scalingFactor = 1
    info.dictionary()[NSPrintInfo.AttributeKey.copies] = settings.copies
    info.dictionary()[NSPrintInfo.AttributeKey.allPages] = true
    info.jobDisposition = .spool
    // Public PrintCore keys; driver compliance still requires physical qualification.
    info.printSettings["AP_ColorMatchingMode"] = settings.colorHandling == .photatoManages || settings.content == .separations ? "AP_ApplicationColorMatching" : "AP_VendorColorMatching"
    return info
  }
  func resolvedPrintSettings(_ settings: PrintSettings, base: NSPrintInfo? = nil) throws -> PrintSettings {
    var resolved = settings
    // A disconnected remembered printer must not prevent PDF preview/output.
    if !settings.printerName.isEmpty && !NSPrinter.printerNames.contains(settings.printerName) {
      _ = try PrintLayout(document: store.document, settings: settings); return settings
    }
    let info = try info(for: settings, base: base)
    if NSPrinter.printerNames.contains(info.printer.name) {
      let bounds = info.imageablePageBounds.intersection(CGRect(origin: .zero, size: info.paperSize))
      guard !bounds.isEmpty else { throw CraftError.invalid("The printer reports no printable area for this media.") }
      resolved.marginLeft = max(settings.marginLeft, bounds.minX); resolved.marginBottom = max(settings.marginBottom, bounds.minY)
      resolved.marginRight = max(settings.marginRight, info.paperSize.width - bounds.maxX)
      resolved.marginTop = max(settings.marginTop, info.paperSize.height - bounds.maxY)
    }
    _ = try PrintLayout(document: store.document, settings: resolved); return resolved
  }
  @discardableResult func startPrinting(_ settings: PrintSettings, authorized: @escaping @MainActor () -> Bool = { true }) throws -> UUID {
    guard canBeginPrint else { throw CraftError.invalid("Finish the current document interaction before printing.") }
    let settings = try resolvedPrintSettings(settings)
    let info = try info(for: settings)
    guard printRunner != nil || (windowForSheet != nil && NSPrinter.printerNames.contains(info.printer.name)) else {
      throw CraftError.invalid("Choose an available printer in a document window before printing.")
    }
    try store.setPrintSettings(settings)
    let source = store.document, proof = store.proofSettings, id = UUID()
    store.printBusy = true; store.printOperationID = id; store.printJobStatus = "preparing"; store.printJobError = nil; store.printRevision = UUID()
    store.printCancellation = { [weak self] in self?.cancelPrintPreparation(id) }
    let expectedRevision = store.printRevision
    printTask = Task { [weak self] in
      guard let self else { return }
      do {
        let worker = Task.detached(priority: .userInitiated) { try PrintOutput.prepare(source, settings: settings, proof: proof) }
        let output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard authorized(), store.document == source, store.printRevision == expectedRevision, store.printOperationID == id,
          closeWorkflowID == nil else { throw CraftError.invalid("Printing cancelled because the document changed or access ended.") }
        store.printJobStatus = "submitted"; store.printRevision = UUID()
        let completion: @MainActor (Bool) -> Void = { [weak self] success in
          guard let self, self.store.printOperationID == id else { return }
          self.store.printCancellation = nil; self.store.printBusy = false; self.store.printJobStatus = success ? "completed" : "cancelledOrFailed"
          self.store.printRevision = UUID(); self.printJob = nil; self.printTask = nil
          self.store.status = success ? "Print operation completed" : "Print operation cancelled or failed"
        }
        if let printRunner { printRunner(output, info, completion) }
        else if let window = windowForSheet {
          let job = NativePrintJob(); printJob = job; job.run(output, info: info, window: window, completion: completion)
        } else { throw CraftError.invalid("The document window closed before printing.") }
      } catch {
        guard store.printOperationID == id else { return }
        store.printCancellation = nil; store.printBusy = false; store.printJobStatus = error is CancellationError ? "cancelled" : "failed"
        store.printJobError = error is CancellationError ? nil : error.localizedDescription
        store.printRevision = UUID(); printTask = nil
      }
    }
    return id
  }
  func cancelPrintPreparation(_ id: UUID? = nil) {
    guard id == nil || store.printOperationID == id, store.printJobStatus == "preparing" else { return }
    printTask?.cancel()
  }
  func resetPrintWorkspace() {
    cancelPrintPreparation(); store.printWorkspace?.close(); store.printWorkspace = nil; store.printAfterDismiss = nil
  }
}
extension AppDelegate {
  @objc func printDocument() { (controller.currentDocument as? CraftNSDocument)?.beginPrint() }
  @objc func printOneCopy() {
    guard let document = controller.currentDocument as? CraftNSDocument else { return }
    var settings = document.store.printSettings; settings.copies = 1
    do { try document.startPrinting(settings) } catch { document.store.error = error.localizedDescription }
  }
}

@MainActor @Observable final class PrintWorkspace: Identifiable {
  let id = UUID()
  weak var owner: CraftNSDocument?
  let source: CraftDocument
  let proof: ProofSettings
  @ObservationIgnored var driverInfo: NSPrintInfo
  var settings: PrintSettings
  var output: PreparedPrint?
  var page = 0
  var rendering = false
  var error: String?
  @ObservationIgnored var task: Task<Void, Never>?
  @ObservationIgnored var generation = UUID()
  init(_ owner: CraftNSDocument) {
    self.owner = owner; driverInfo = (owner.rememberedPrintInfo ?? owner.printInfo).copy() as! NSPrintInfo; source = owner.store.document; proof = owner.store.proofSettings; settings = owner.store.printSettings
    if settings.printerName.isEmpty, NSPrinter.printerNames.contains(driverInfo.printer.name) { settings.printerName = driverInfo.printer.name }
  }
  func close() { generation = UUID(); task?.cancel(); task = nil }
  func refresh() {
    close(); rendering = true; error = nil; output = nil
    do { if let owner { settings = try owner.resolvedPrintSettings(settings, base: driverInfo) } }
    catch { self.error = error.localizedDescription; rendering = false; return }
    let expected = generation, source = source, settings = settings, proof = proof
    task = Task { [weak self] in
      do {
        let worker = Task.detached(priority: .userInitiated) { try PrintOutput.prepare(source, settings: settings, proof: proof) }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        guard let self, generation == expected, !Task.isCancelled else { return }
        output = result; page = min(page, result.pages.count - 1); rendering = false
      } catch {
        guard let self, generation == expected, !Task.isCancelled else { return }
        self.error = error.localizedDescription; rendering = false
      }
    }
  }
  func accept(printNow: Bool) {
    guard let owner, output != nil, !rendering, owner.store.document == source else { return }
    do {
      try owner.store.setPrintSettings(settings); owner.rememberedPrintInfo = driverInfo; let settings = settings, source = source
      if printNow {
        owner.store.printAfterDismiss = { [weak owner] in
          guard let owner, owner.store.document == source else { return }
          do { try owner.startPrinting(settings) } catch { owner.store.error = error.localizedDescription }
        }
      }
      close(); owner.store.printWorkspace = nil
    } catch { self.error = error.localizedDescription }
  }
  func cancel() { close(); owner?.store.printWorkspace = nil }
  func driverSettings() {
    guard let owner else { return }
    do {
      let candidate = try owner.info(for: settings, base: driverInfo), panel = NSPrintPanel()
      panel.options = [.showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation]
      guard panel.runModal(with: candidate) == NSApplication.ModalResponse.OK.rawValue else { return }
      driverInfo = candidate
      settings.printerName = candidate.printer.name
      settings.paper = .custom; settings.orientation = candidate.orientation == .landscape ? .landscape : .portrait
      settings.customWidth = candidate.orientation == .landscape ? candidate.paperSize.height : candidate.paperSize.width
      settings.customHeight = candidate.orientation == .landscape ? candidate.paperSize.width : candidate.paperSize.height
      let bounds = candidate.imageablePageBounds
      settings.marginLeft = max(0, bounds.minX); settings.marginBottom = max(0, bounds.minY)
      settings.marginRight = max(0, candidate.paperSize.width - bounds.maxX); settings.marginTop = max(0, candidate.paperSize.height - bounds.maxY)
      settings.copies = min(999, max(1, (candidate.dictionary()[NSPrintInfo.AttributeKey.copies] as? NSNumber)?.intValue ?? 1))
      refresh()
    } catch { self.error = error.localizedDescription }
  }
  func chooseProfile() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "icc") ?? .data, UTType(filenameExtension: "icm") ?? .data]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max <= ICCProfile.maximumBytes else { throw CraftError.invalid("The profile is too large.") }
      let data = try Data(contentsOf: url); _ = try ProofSettings.mode(of: data)
      settings.profile = data; settings.profileName = url.deletingPathExtension().lastPathComponent; settings.colorHandling = .photatoManages; refresh()
    } catch { self.error = error.localizedDescription }
  }
  func savePDF() {
    guard let output, !rendering else { return }
    let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = source.name + ".pdf"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    Task { [weak self] in
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        try await Task.detached(priority: .userInitiated) {
          let data = try output.pdf(), writer = try AtomicFileWriter(to: url, maximumBytes: DocumentIO.maximumDownloadBytes)
          try writer.append(data); try writer.commit()
        }.value
        self?.owner?.store.status = "Saved print PDF"
      } catch { self?.error = error.localizedDescription }
    }
  }
}

private struct PrintPreview: NSViewRepresentable {
  let output: PreparedPrint
  let page: Int
  func makeNSView(context: Context) -> PrintPageView { PrintPageView(output, previewPage: page) }
  func updateNSView(_ view: PrintPageView, context: Context) { view.previewPage = page; view.needsDisplay = true }
}
struct PrintSheet: View {
  @Bindable var model: PrintWorkspace
  var body: some View {
    VStack(spacing: 14) {
      HStack { Text("Print").font(.title2); Spacer(); Text(model.source.name).foregroundStyle(.secondary) }
      HStack(alignment: .top, spacing: 20) {
        VStack {
          if let output = model.output {
            PrintPreview(output: output, page: model.page).id(model.generation).frame(maxWidth: .infinity, maxHeight: .infinity).background(.gray.opacity(0.15)).clipped()
            if output.pages.count > 1 { Picker("Plate", selection: $model.page) { ForEach(output.pages.indices, id: \.self) { Text(output.pages[$0].label).tag($0) } } }
            Text(String(format: "%.1f%% · %.1f ppi · %.2f × %.2f in", output.layout.scalePercent, output.layout.effectivePPI, output.layout.image.width / 72, output.layout.image.height / 72)).font(.caption)
            if output.layout.clipped { Text("The image extends beyond the printable area and will be clipped.").foregroundStyle(.orange).font(.caption) }
          } else if model.rendering { ProgressView("Preparing print preview…").frame(maxWidth: .infinity, maxHeight: .infinity) }
          else { Text("Choose valid print settings to preview this page.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.frame(width: 365)
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            GroupBox("Printer Setup") {
              VStack(alignment: .leading) {
                Picker("Printer", selection: $model.settings.printerName) {
                  Text("System default / PDF").tag("")
                  ForEach(NSPrinter.printerNames, id: \.self) { Text($0).tag($0) }
                }
                HStack { TextField("Copies", value: $model.settings.copies, format: .number).frame(width: 110); Spacer(); Button("Print Settings…", action: model.driverSettings) }
                Picker("Paper", selection: $model.settings.paper) { ForEach(PrintSettings.Paper.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Orientation", selection: $model.settings.orientation) { Text("Portrait").tag(PrintSettings.Orientation.portrait); Text("Landscape").tag(PrintSettings.Orientation.landscape) }
                if model.settings.paper == .custom { HStack { number("Width (pt)", $model.settings.customWidth); number("Height (pt)", $model.settings.customHeight) } }
              }.padding(6)
            }
            GroupBox("Position and Size") {
              VStack(alignment: .leading) {
                Toggle("Center", isOn: $model.settings.center)
                HStack { number("Top (pt)", $model.settings.top); number("Left (pt)", $model.settings.left) }.disabled(model.settings.center)
                Toggle("Scale to Fit Media", isOn: $model.settings.scaleToFit)
                number("Scale (%)", $model.settings.scalePercent).disabled(model.settings.scaleToFit)
                Toggle("Print Selected Area", isOn: $model.settings.selectedArea).disabled(model.source.selection == nil && model.source.selectionMask == nil)
              }.padding(6)
            }
            GroupBox("Color Management") {
              VStack(alignment: .leading) {
                Picker("Print", selection: $model.settings.content) { Text("Document").tag(PrintSettings.Content.document); Text("Hard Proofing").tag(PrintSettings.Content.hardProof); Text("Separations").tag(PrintSettings.Content.separations) }
                if model.settings.content == .hardProof { Text("Proof Setup: " + model.proof.displayName).font(.caption); Text("Uses the current Proof Setup profile, intent and preserved numbers.").font(.caption).foregroundStyle(.secondary); Toggle("Simulate Paper Color", isOn: $model.settings.simulatePaper); Toggle("Simulate Black Ink", isOn: $model.settings.simulateBlack).disabled(model.settings.simulatePaper) }
                Picker("Color Handling", selection: $model.settings.colorHandling) { Text("Printer Manages Colors").tag(PrintSettings.ColorHandling.printerManages); Text("Photato Manages Colors").tag(PrintSettings.ColorHandling.photatoManages) }.disabled(model.settings.content == .separations)
                if model.settings.colorHandling == .photatoManages && model.settings.content != .separations {
                  Text(model.settings.profileName.isEmpty ? "No printer/paper profile selected" : model.settings.profileName).lineLimit(2)
                  Button("Choose Printer Profile…", action: model.chooseProfile)
                  Picker("Rendering Intent", selection: $model.settings.intent) { ForEach(ModeRenderingIntent.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.disabled(model.settings.content == .hardProof)
                  Toggle("Black Point Compensation", isOn: $model.settings.blackPointCompensation).disabled(model.settings.content == .hardProof)
                  Text("Disable color correction in the printer driver to avoid a second conversion.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Send 16-bit Data", isOn: $model.settings.sixteenBit)
              }.padding(6)
            }
            GroupBox("Printing Marks") {
              VStack(alignment: .leading) {
                Toggle("Corner Crop Marks", isOn: $model.settings.cornerCropMarks)
                Toggle("Center Crop Marks", isOn: $model.settings.centerCropMarks)
                Toggle("Registration Marks", isOn: $model.settings.registrationMarks)
                Toggle("Labels", isOn: $model.settings.labels)
                TextField("Description", text: $model.settings.description)
                HStack { number("Border (pt)", $model.settings.border); number("Bleed (pt)", $model.settings.bleed) }
              }.padding(6)
            }
          }.padding(.trailing, 8)
        }.frame(width: 405)
      }
      if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
      HStack {
        Button("Save PDF…", action: model.savePDF).disabled(model.rendering || model.output == nil)
        Spacer(); Button("Cancel", action: model.cancel).keyboardShortcut(.cancelAction)
        Button("Done") { model.accept(printNow: false) }.disabled(model.output == nil || model.rendering)
        Button("Print") { model.accept(printNow: true) }.keyboardShortcut(.defaultAction).disabled(model.output == nil || model.rendering || NSPrinter.printerNames.isEmpty)
      }
    }.padding(20).frame(width: 830, height: 640)
      .onChange(of: model.settings) { _, _ in model.refresh() }
      .onDisappear { model.close() }
  }
  private func number(_ title: String, _ value: Binding<Double>) -> some View {
    HStack { Text(title).font(.caption); TextField(title, value: value, format: .number.precision(.fractionLength(0...2))).textFieldStyle(.roundedBorder) }
  }
}
