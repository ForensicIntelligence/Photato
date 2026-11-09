import Foundation
import ImageIO
import PhotoCraftAI
import PhotoCraftCore

enum EditPlanAPI {
  static var operationSchema: [String: Any] {
    var choices: [[String: Any]] = [["type": "string", "enum": NativeEditOperation.allCases.map(\.rawValue)]]
    for kind in NativeEditAdjustment.Kind.allCases {
      var fields: [String: Any] = [:]
      for parameter in kind.parameters {
        fields[parameter.name] = ["type": parameter.integer ? "integer" : "number", "minimum": parameter.minimum,
          "maximum": parameter.maximum, "description": parameter.unit.isEmpty ? parameter.title : parameter.title + " (" + parameter.unit + ")"]
      }
      choices.append(BrushAPI.object(["operation": ["const": kind.rawValue],
        "parameters": BrushAPI.object(fields, required: kind.parameters.map(\.name))], required: ["operation", "parameters"]))
    }
    return ["oneOf": choices]
  }
  static var planSchema: [String: Any] {
    BrushAPI.object(["summary": ["type": "string", "minLength": 1, "maxLength": 512, "description": "Nonblank; additionally limited to512UTF-8bytes."],
      "operations": ["type": "array", "minItems": 1, "maxItems": 8, "items": operationSchema]], required: ["summary", "operations"])
  }
  static var controlSchema: [String: Any] {
    let common: [String: Any] = ["revision": ["type": "string"], "requestID": ["type": "string", "format": "uuid"]]
    return ["oneOf": [
      BrushAPI.object(["operation": ["const": "prepare"], "revision": common["revision"]!, "plan": planSchema], required: ["operation", "revision", "plan"]),
      BrushAPI.object(["operation": ["type": "string", "enum": ["apply", "cancel"]], "revision": common["revision"]!, "requestID": common["requestID"]!], required: ["operation", "revision", "requestID"])]]
  }
  static var stateSchema: [String: Any] {
    let optionalUUID: [String: Any] = ["anyOf": [["type": "string", "format": "uuid"], ["type": "null"]]]
    return BrushAPI.object(["requestID": optionalUUID, "phase": ["type": "string", "enum": ["idle", "planning", "preparing", "ready", "failed", "cancelled", "applied"]],
      "origin": ["anyOf": [["type": "string", "enum": ["supplied", "onDevice", "privateCloudCompute"]], ["type": "null"]]],
      "plan": ["anyOf": [planSchema, ["type": "null"]]], "canPrepare": ["type": "boolean"], "canApply": ["type": "boolean"],
      "error": ["anyOf": [["type": "string"], ["type": "null"]]], "revision": ["type": "string"],
      "providers": ["type": "array", "items": BrushAPI.object(["id": ["type": "string", "enum": EditPlanProvider.allCases.map(\.rawValue)], "available": ["type": "boolean"], "message": ["type": "string"], "reason": AICapabilityAPI.reasonSchema], required: ["id", "available", "message", "reason"])],
      "workspaceSection": ["type": "string", "enum": ["image", "editPlan"]], "workspacePresented": ["type": "boolean"]],
      required: ["requestID", "phase", "origin", "plan", "canPrepare", "canApply", "error", "providers", "workspaceSection", "workspacePresented"])
  }
  static var capabilities: [String: Any] {
    ["statePath": "GET /v1/documents/{id}/edit-plan", "controlPath": "POST /v1/documents/{id}/edit-plan",
      "previewPath": "GET /v1/documents/{id}/edit-plan/previews/{before|after}",
      "controlSchema": controlSchema, "stateSchema": stateSchema, "planSchema": planSchema,
      "operations": NativeEditOperation.supportedNames,
      "fixedOperations": NativeEditOperation.allCases.map(\.rawValue), "operationSchema": operationSchema,
      "adjustmentValues": "Each adjustment requires exactly its declared numeric parameters. Exposure uses EV, Offset and Gamma Correction; Brightness/Contrast uses integer UI values with Legacy off; Hue/Saturation uses master hue degrees and saturation/lightness percent with Colorize off; Vibrance uses integer vibrance and saturation. Every value is displayed before Apply. Unknown keys, booleans, missing/nonfinite/out-of-range/fractional integer values reject without changing the source.",
      "presentation": "Native segmented Workflow selector in the existing Apple Intelligence sheet. Each presentation starts in Create Image. Section and presentation state are observable and included in the opaque revision; switching is disabled until current AI work finishes or is cancelled. Supplied-plan HTTP operations do not open a modal or run a model.",
      "generation": "Native Edit > Create with Apple Intelligence > Edit Plan explicitly selects on-device26+ or Private Cloud Compute27+ text planning. Only the instruction is sent; no pixels, file paths, document/layer names or arbitrary tools. The running app must carry Apple's managed PCC entitlement for direct cloud text use; runtime availability still applies. Discovery reports stable reason codes. HTTP accepts supplied typed plans; it never starts inference or labels supplied plans as model output.",
      "transaction": "Prepare computes actual before/after previews and a retained native Actions transaction without changing document/history. Apply requires the matching requestID/current revision and exact source session/lifecycle/target. One Undo/Redo transaction; a no-op adds no history. Cancel discards retained work; no clipboard, files, scripts, selection or layer-target code is supplied by the plan.",
      "authorization": "Prepare/apply/cancel require native Allow workspace panel changes, a current bearer token and shared document revision. Preview PNG downloads also require document transfers and X-Photato-Revision. Sharing/token/permissions/source are checked again after detached work.",
      "preview": "SDR color-managed full-canvas overview, maximum2048 per side; native editing values retain their original depth. Existing renderer/operation capacity limits still apply.",
      "remaining": "Five fixed corrections and four bounded parameterized adjustments on one RGB pixel layer only. Native kernel/output differences remain; general assistant guidance, image understanding, generative editing, arbitrary tools, AI Assisted Editor and actual provider-output/platform qualification remain open.",
      "adobe": "No corresponding reviewed desktop-plan lifecycle is defined by the pinned Firefly v2 contract. No Adobe endpoint or proprietary AI runtime/output equivalence is claimed."]
  }
  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    let review = store.editPlanReview
    let plan = review?.plan.flatMap { plan -> Any? in
      guard let bytes = try? JSONEncoder().encode(plan) else { return nil }
      return try? JSONSerialization.jsonObject(with: bytes)
    }
    return ["requestID": review?.id.uuidString as Any? ?? NSNull(), "phase": review?.phase ?? "idle",
      "origin": review?.origin.rawValue as Any? ?? NSNull(), "plan": plan as Any? ?? NSNull(),
      "canPrepare": store.canReviewEditPlan, "canApply": store.canApplyEditPlan, "error": review?.error as Any? ?? NSNull(),
      "providers": EditPlanProvider.allCases.map { provider in
        var value = AICapabilityAPI.state(provider.capability); value["id"] = provider.rawValue; return value
      },
      "workspaceSection": store.aiWorkspaceSection.rawValue, "workspacePresented": store.showAI]
  }
}

extension AutomationService {
  func controlEditPlan(_ request: AutomationRequest, share: Share, document: CraftNSDocument) async throws -> AutomationResponse {
    guard workspacePanelChangesEnabled else { throw AutomationFailure(status: 403, message: "Allow workspace panel changes before reviewing an edit plan.") }
    guard let fields = try JSONSerialization.jsonObject(with: request.body) as? [String: Any],
      let operation = fields["operation"] as? String, let expected = fields["revision"] as? String else {
      throw AutomationFailure(status: 400, message: "An edit-plan operation and current revision are required.")
    }
    let store = document.store
    guard revision(store) == expected else { throw AutomationFailure(status: 409, message: "The document revision is stale.") }
    if operation == "prepare" {
      guard Set(fields.keys) == ["operation", "revision", "plan"], let value = fields["plan"] else { throw AutomationFailure(status: 400, message: "Prepare requires only operation, revision and plan.") }
      let plan: NativeEditPlan
      do { plan = try NativeEditPlan.decode(JSONSerialization.data(withJSONObject: value)) }
      catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
      try preflight(document)
      guard store.canReviewEditPlan else { throw AutomationFailure(status: 422, message: "Select one unlocked RGB pixel layer.") }
      let expectedToken = token, expectedGeneration = generation
      let sourceRevision = revision(store, includeEditPlan: false)
      try await store.prepareReviewedEditPlan(plan) { [self] in
        prune()
        guard isRunning, token == expectedToken, generation == expectedGeneration, workspacePanelChangesEnabled,
          shares.contains(where: { $0.id == share.id && $0.document === document }),
          revision(store, includeEditPlan: false) == sourceRevision else {
          throw AutomationFailure(status: 409, message: "The edit plan source, sharing or permissions changed.")
        }
      }
    } else if operation == "apply" || operation == "cancel" {
      guard Set(fields.keys) == ["operation", "revision", "requestID"], let text = fields["requestID"] as? String,
        let id = UUID(uuidString: text), store.editPlanReview?.id == id else { throw AutomationFailure(status: 409, message: "The edit-plan request is stale or invalid.") }
      if operation == "cancel" { store.cancelReviewedEditPlan() }
      else {
        try preflight(document)
        guard store.canApplyEditPlan else { throw AutomationFailure(status: 409, message: "Prepare a current edit-plan preview before applying it.") }
        if let prepared = store.editPlanReview?.prepared {
          var candidate = store.session; try candidate.executePrepared(prepared.edit)
          try Self.checkLimits(candidate.document)
        }
        try store.applyReviewedEditPlan(id)
      }
    } else { throw AutomationFailure(status: 400, message: "Unknown edit-plan operation.") }
    var result = EditPlanAPI.state(store); result["revision"] = revision(store)
    return .json(result)
  }
  func editPlanPreview(_ side: String, request: AutomationRequest, share: Share, document: CraftNSDocument) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Allow document transfers before downloading an edit preview.") }
    let store = document.store
    guard ["before", "after"].contains(side), let review = store.editPlanReview, store.canApplyEditPlan,
      let prepared = review.prepared, request.headers["x-photato-revision"] == revision(store) else {
      throw AutomationFailure(status: 409, message: "The edit preview or requested revision is stale.")
    }
    let image = side == "before" ? prepared.before : prepared.after
    let expectedToken = token, expectedGeneration = generation, expected = revision(store)
    let worker = Task.detached(priority: .userInitiated) {
      let bytes = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else { throw CraftError.invalid("Cannot encode an edit preview.") }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { throw CraftError.invalid("Cannot encode an edit preview.") }
      try Task.checkCancellation(); return bytes as Data
    }
    let bytes = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation(); prune()
    guard isRunning, token == expectedToken, generation == expectedGeneration, documentTransfersEnabled,
      shares.contains(where: { $0.id == share.id && $0.document === document }), revision(store) == expected,
      store.editPlanReview === review, store.canApplyEditPlan else { throw AutomationFailure(status: 409, message: "Edit preview sharing or source changed.") }
    return AutomationResponse(status: 200, contentType: "image/png", body: bytes)
  }
}
