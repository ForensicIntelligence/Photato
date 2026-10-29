import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PrintAPI {
  static let commands = ["print.configure", "print.settings.read", "print.present", "print.submit", "print.cancel"]
  static var settings: [String: Any] { BrushAPI.object([
    "paper": BrushAPI.enumeration(PrintSettings.Paper.allCases.map(\.rawValue)),
    "orientation": BrushAPI.enumeration(PrintSettings.Orientation.allCases.map(\.rawValue)),
    "customWidth": BrushAPI.number(18, 14_400), "customHeight": BrushAPI.number(18, 14_400),
    "marginTop": BrushAPI.number(0, 14_400), "marginLeft": BrushAPI.number(0, 14_400),
    "marginBottom": BrushAPI.number(0, 14_400), "marginRight": BrushAPI.number(0, 14_400),
    "center": BrushAPI.flag, "scaleToFit": BrushAPI.flag, "scalePercent": BrushAPI.number(0.01, 10_000),
    "top": BrushAPI.number(-144_000, 144_000), "left": BrushAPI.number(-144_000, 144_000),
    "selectedArea": BrushAPI.flag, "copies": ["type": "integer", "minimum": 1, "maximum": 999],
    "printerName": ["type": "string", "maxLength": 1024],
    "content": BrushAPI.enumeration(PrintSettings.Content.allCases.map(\.rawValue)),
    "colorHandling": BrushAPI.enumeration(PrintSettings.ColorHandling.allCases.map(\.rawValue)),
    "profile": ["anyOf": [["type": "string", "contentEncoding": "base64", "maxLength": (ICCProfile.maximumBytes + 2) / 3 * 4], ["type": "null"]]],
    "profileName": ["type": "string", "maxLength": 1024],
    "intent": BrushAPI.enumeration(ModeRenderingIntent.allCases.map(\.rawValue)),
    "blackPointCompensation": BrushAPI.flag, "simulatePaper": BrushAPI.flag, "simulateBlack": BrushAPI.flag, "sixteenBit": BrushAPI.flag,
    "cornerCropMarks": BrushAPI.flag, "centerCropMarks": BrushAPI.flag,
    "registrationMarks": BrushAPI.flag, "labels": BrushAPI.flag,
    "description": ["type": "string", "maxLength": 4096],
    "border": BrushAPI.number(0, 72), "bleed": BrushAPI.number(0, 72)], required: []) }
  static func schema(_ key: String) -> [String: Any] { key == "settings" ? settings : ["type": "string", "format": "uuid"] }
  static var stateSchema: [String: Any] { BrushAPI.object([
    "settings": settings, "available": BrushAPI.flag, "workspaceOpen": BrushAPI.flag, "busy": BrushAPI.flag,
    "operationID": ["type": ["string", "null"]], "status": BrushAPI.enumeration(["idle", "preparing", "submitted", "completed", "cancelled", "failed", "cancelledOrFailed"]),
    "error": ["type": ["string", "null"]]], required: ["settings", "available", "workspaceOpen", "busy", "operationID", "status", "error"]) }
  static var capabilities: [String: Any] { [
    "commands": commands, "settings": settings, "stateSchema": stateSchema,
    "resultSchema": BrushAPI.object(["printing": stateSchema, "revision": ["type": "string"]], required: ["printing", "revision"]),
    "pdfRoute": "/v1/documents/{id}/print.pdf", "maximumPixels": SoftProof.maximumPixels,
    "maximumPreparedBytes": PreparedPrint.maximumBytes, "maximumPDFBytes": DocumentIO.maximumDownloadBytes,
    "units": "All physical dimensions and margins are points (72 per inch). Top/left are measured from paper top-left. Custom width/height describe portrait media; orientation rotates it. Center uses the printable area center. Scale to Fit reserves space for marks inside the printable bounds.",
    "behavior": "Settings are per-document output state, excluded from pixels, history and archives. Configure merges validated fields and advances the view revision. PDF uses committed settings and proof condition; copies apply only to printer submission, not PDF pages. Selected area uses the rectangular selection bounds, not its feathered mask. Hard proofs require Photato-managed color and a printer ICC profile. Screen gamut overlays never print. Retained flat component samples bypass the RGB display cache; complex stacks use their RGB composite. Separations preserve flat CMYK ink values or Duotone/Multichannel densities as one grayscale page per plate.",
    "printerPermission": "print.present and print.submit require Allow printing, off by default and reset when the API stops. Submitting is an explicit printer job. Cancellation/revocation stops preparation; submitted jobs must be managed in the macOS print queue. completed means AppKit completed its operation, not verified physical delivery. Driver media/color settings may affect output.",
    "limits": "Physical printer and live dialog acceptance, device-specific color behavior, arbitrary layered component separations, PostScript screen/transfer functions, DeviceN overprint, print Actions/persistence and exact Photoshop output remain open. 32-bit content is mapped to bounded8/16-bit print output. No unpublished Adobe print route is invented."] }
}
extension AutomationCommand {
  func printSettings(base: PrintSettings, document: CraftDocument) throws -> PrintSettings {
    guard let value = parameters["settings"] else { throw AutomationFailure(status: 400, message: "Print settings are required.") }
    let merged = try BrushAPI.merge(value, schema: PrintAPI.settings, base: BrushAPI.json(base), path: "print settings")
    let result: PrintSettings
    do { result = try JSONDecoder().decode(PrintSettings.self, from: JSONSerialization.data(withJSONObject: merged)) }
    catch { throw AutomationFailure(status: 400, message: "Invalid print settings: \(error.localizedDescription)") }
    _ = try PrintLayout(document: document, settings: result); return result
  }
}
extension EditorStore {
  var printState: [String: Any] { ["settings": BrushAPI.json(printSettings), "available": canBeginPrint,
    "workspaceOpen": printWorkspace != nil, "busy": printBusy, "operationID": printOperationID?.uuidString as Any? ?? NSNull(),
    "status": printJobStatus, "error": printJobError as Any? ?? NSNull()] }
}
extension AutomationService {
  func setPrintingEnabled(_ enabled: Bool) {
    printingGeneration = UUID(); printingEnabled = enabled && isRunning
    if !printingEnabled { for share in shares { cancelSharedPrint(share) } }
  }
  func cancelSharedPrint(_ share: Share) {
    if let id = ownedPrints.removeValue(forKey: share.id) { share.document?.cancelPrintPreparation(id) }
  }
  func printPDF(_ share: Share, document: CraftNSDocument) async throws -> AutomationResponse {
    try Self.checkLimits(document.store.document)
    guard !previewBusy else { throw AutomationFailure(status: 429, message: "A preview or PDF is already rendering.") }
    previewBusy = true; defer { previewBusy = false }
    let store = document.store, source = store.document, settings = store.printSettings, proof = store.proofSettings
    let expected = revision(store), expectedGeneration = generation
    let worker = Task.detached(priority: .utility) { try PrintOutput.prepare(source, settings: settings, proof: proof).pdf() }
    let bytes = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    prune()
    guard !Task.isCancelled, generation == expectedGeneration, revision(store) == expected, shares.contains(where: { $0.id == share.id }) else {
      throw AutomationFailure(status: 409, message: "Document changed or sharing ended during print rendering.")
    }
    return .init(status: 200, contentType: "application/pdf", body: bytes)
  }
  func executePrint(_ command: AutomationCommand, share: Share, document: CraftNSDocument) throws -> AutomationResponse {
    let store = document.store
    switch command.name {
    case "print.configure": try store.setPrintSettings(document.resolvedPrintSettings(command.printSettings(base: store.printSettings, document: store.document)))
    case "print.present", "print.submit":
      guard printingEnabled else { throw AutomationFailure(status: 403, message: "Enable Allow printing in the native Automation window first.") }
      if command.name == "print.present" {
        guard document.canBeginPrint else { throw AutomationFailure(status: 409, message: "The document is busy.") }; document.beginPrint()
      } else {
        let expected = printingGeneration, session = generation
        let id = try document.startPrinting(store.printSettings) { [weak self, weak document] in
          guard let self, let document else { return false }; self.prune()
          return self.printingEnabled && self.printingGeneration == expected && self.generation == session && self.shares.contains { $0.id == share.id && $0.document === document }
        }
        ownedPrints[share.id] = id
      }
    case "print.cancel":
      let id = try command.actionUUID("operationID")
      guard ownedPrints[share.id] == id, store.printOperationID == id, store.printJobStatus == "preparing" else {
        throw AutomationFailure(status: 409, message: "This API session has no matching print preparation. Manage submitted jobs in the macOS print queue.")
      }
      document.cancelPrintPreparation(id)
    default: break
    }
    return .json(["printing": store.printState, "revision": revision(store)])
  }
}
