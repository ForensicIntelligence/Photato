import AppKit
import PhotoCraftCore

public struct ColorPolicyChoice: Equatable, Sendable {
  public enum Action: String, CaseIterable, Sendable {
    case preserveEmbedded, convertToWorking, discard, leaveUntagged, assignWorking, assignProfile
    case convertAppearance, preserveNumbers
  }
  public var action: Action
  public var profile: Data?
  public init(_ action: Action, profile: Data? = nil) { self.action = action; self.profile = profile }
}
public struct ColorPolicyAssessment: Equatable, Sendable {
  public enum Kind: String, Sendable { case none, missing, mismatch, pasteMismatch }
  public let kind: Kind
  public let source: String
  public let destination: String
  public let choices: [ColorPolicyChoice.Action]
  public let requiresReview: Bool
}
public struct ColorPolicyReviewNeeded: Error, LocalizedError, Sendable {
  public let assessment: ColorPolicyAssessment
  public var errorDescription: String? { "A color profile decision is required before this operation can continue." }
}
public enum ColorPolicyInput {
  public static func name(_ profile: Data) -> String {
    CGColorSpace(iccData: profile as CFData).flatMap { NSColorSpace(cgColorSpace: $0)?.localizedName } ?? "Custom ICC profile"
  }
  public static func openingAssessment(_ document: CraftDocument, settings: ColorSettings) throws -> ColorPolicyAssessment {
    guard ColorSettings.workingModes.contains(document.colorMode) else {
      return .init(kind: .none, source: document.colorMode.title, destination: document.colorMode.title, choices: [], requiresReview: false)
    }
    let working = try settings.profile(document.colorMode, depth: document.depth)
    let missing = document.profileIsUntagged == true
    let mismatch = try !missing && ColorProfileInput.effectiveProfile(document) != working
    return .init(kind: missing ? .missing : mismatch ? .mismatch : .none,
      source: ColorProfileInput.name(document), destination: name(working),
      choices: missing ? [.leaveUntagged, .assignWorking, .assignProfile] : [.preserveEmbedded, .convertToWorking, .discard],
      requiresReview: missing ? settings.askMissingOpening : mismatch && settings.askMismatchOpening)
  }
  public static func opening(_ document: CraftDocument, settings: ColorSettings, choice: ColorPolicyChoice? = nil) throws -> CraftDocument {
    let assessment = try openingAssessment(document, settings: settings)
    guard !assessment.choices.isEmpty else {
      guard choice == nil else { throw CraftError.unsupported("This document mode has no RGB/CMYK/Gray opening policy.") }
      return document
    }
    if choice == nil && assessment.requiresReview { throw ColorPolicyReviewNeeded(assessment: assessment) }
    let action: ColorPolicyChoice.Action
    if let choice {
      guard assessment.choices.contains(choice.action), (choice.action == .assignProfile) == (choice.profile != nil) else {
        throw CraftError.invalid("The color profile decision does not match this document.")
      }
      action = choice.action
    } else if assessment.kind == .missing {
      action = .leaveUntagged
    } else {
      switch settings.policy(document.colorMode) {
      case .preserveEmbedded: action = .preserveEmbedded
      case .convertToWorking: action = .convertToWorking
      case .off: action = .discard
      }
    }
    if action == .preserveEmbedded { return document }
    let profile = try choice?.profile ?? settings.profile(document.colorMode, depth: document.depth)
    if action == .convertToWorking, try ColorProfileInput.effectiveProfile(document) == profile { return document }
    var request = ColorProfileRequest(action == .convertToWorking ? .convert : .assign, profile: profile)
    request.intent = settings.intent; request.blackPointCompensation = settings.blackPointCompensation
    request.removeProfile = action == .discard || action == .leaveUntagged
    if request.removeProfile, document.profileIsUntagged == true,
      try ColorProfileInput.effectiveProfile(document) == profile { return document }
    var result = document; try ColorProfileInput.command(request, in: document).apply(to: &result)
    return result
  }
  public static func pasteAssessment(_ content: ClipboardContent, into target: CraftDocument, settings: ColorSettings) throws -> ColorPolicyAssessment {
    let source = content.document
    guard DocumentColorMode.componentModes.contains(source.colorMode), DocumentColorMode.componentModes.contains(target.colorMode) else {
      return .init(kind: .none, source: source.colorMode.title, destination: target.colorMode.title, choices: [], requiresReview: false)
    }
    let from = try ColorProfileInput.effectiveProfile(source)
    let to = try ColorProfileInput.effectiveProfile(target)
    let different = source.colorMode != target.colorMode || from != to
    let numbers = source.colorMode == target.colorMode && (source.depth == .f32) == (target.depth == .f32)
    return .init(kind: different ? .pasteMismatch : .none,
      source: ColorProfileInput.name(source), destination: ColorProfileInput.name(target),
      choices: numbers ? [.convertAppearance, .preserveNumbers] : [.convertAppearance],
      requiresReview: different && settings.askMismatchPasting)
  }
  public static func pasteCommand(_ content: ClipboardContent, into target: CraftDocument, settings: ColorSettings,
    choice: ColorPolicyChoice? = nil, placement: PastePlacement = .centered, center: PathPoint? = nil) throws -> Command {
    let assessment = try pasteAssessment(content, into: target, settings: settings)
    if choice == nil && assessment.requiresReview { throw ColorPolicyReviewNeeded(assessment: assessment) }
    if let choice, !assessment.choices.contains(choice.action) || choice.profile != nil {
      throw CraftError.invalid("This color profile decision is unavailable for the paste.")
    }
    guard assessment.kind == .pasteMismatch else {
      return try ClipboardRenderer.pasteCommand(content, into: target, placement: placement, center: center)
    }
    let preserve = choice?.action == .preserveNumbers || (choice == nil && assessment.choices.contains(.preserveNumbers)
      && (settings.policy(target.colorMode) == .off || target.profileIsUntagged == true))
    if preserve, target.modeDescriptor != nil, placement == .into || placement == .outside {
      throw CraftError.unsupported("Preserving component numbers with Paste Into/Outside requires a direct component selection workflow.")
    }
    var input = content
    input.restrictedSamples = nil
    if !target.colorMode.depths.contains(input.document.depth) {
      // CMYK/Lab have no Float32 representation. A lower-depth destination
      // already entails clipping; reduce the copied content before conversion.
      let sourceProfile = try NativeModeProfile.atDepth(ColorProfileInput.effectiveProfile(input.document),
        mode: input.document.colorMode, depth: target.depth)
      let reduction = DocumentModeRequest(.init(mode: input.document.colorMode, depth: target.depth,
        profile: sourceProfile, intent: settings.intent), clipHDR: true)
      try DocumentModeInput.command(reduction, in: input.document).apply(to: &input.document)
    }
    let profile = try NativeModeProfile.atDepth(ColorProfileInput.effectiveProfile(target), mode: target.colorMode, depth: input.document.depth)
    var request = ColorProfileRequest(preserve ? .assign : .convert, profile: profile)
    request.intent = settings.intent; request.blackPointCompensation = settings.blackPointCompensation
    try ColorProfileInput.command(request, in: input.document).apply(to: &input.document)
    // Ordinary RGB documents store their profile coordinates directly. Native mode
    // surfaces are display caches, so extract the converted RGB planes instead.
    if target.modeDescriptor == nil {
      for i in input.document.layers.indices {
        guard let native = input.document.layers[i].nativeMode else { continue }
        guard native.mode == .rgb else { throw CraftError.invalid("Paste conversion did not produce RGB components.") }
        var pixels = try Surface(width: native.width, height: native.height, depth: native.depth,
          colorEncoding: native.depth == .f32 ? .linearRGB : .sRGB)
        for y in 0..<native.height { try Task.checkCancellation(); for x in 0..<native.width {
          let index = y * native.width + x
          let value = Pixel(native.value(component: 0, index: index), native.value(component: 1, index: index),
            native.value(component: 2, index: index), native.value(component: 3, index: index))
          if native.depth == .f32 { pixels.setLinearPixel(x: x, y: y, value) } else { pixels.setPixel(x: x, y: y, value) }
        } }
        input.document.layers[i].nativeMode = nil; input.document.layers[i].content = .raster(pixels)
      }
      input.document.modeDescriptor = nil
      // The target may use implicit standard RGB rather than an explicit ICC blob.
      input.document.workingICC = try NativeModeProfile.atDepth(ColorProfileInput.effectiveProfile(target), mode: .rgb, depth: input.document.depth)
      if (input.document.depth == .f32) == (target.depth == .f32) { input.document.workingICC = target.workingICC }
    }
    return try ClipboardRenderer.pasteCommand(input, into: target, placement: placement, center: center)
  }
}
