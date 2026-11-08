import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Stable product states, separate from Apple's evolving SDK enum descriptions.
public enum AICapabilityReason: String, CaseIterable, Sendable {
  case ready, deviceNotEligible, unsupportedSystem, appleIntelligenceNotEnabled
  case modelNotReady, systemNotReady, missingEntitlement, frameworkUnavailable, unknown
}

extension LocalAI {
  /// Reads the running task's signed entitlement, never an Info.plist assertion.
  /// A present bit does not attest Apple account eligibility or service approval.
  public static var privateCloudComputeEntitled: Bool {
    guard let task = SecTaskCreateFromSelf(nil),
      let value = SecTaskCopyValueForEntitlement(
        task, "com.apple.developer.private-cloud-compute" as CFString, nil),
      CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
    return (value as? Bool) == true
  }

  static func cloudTextCapability(majorVersion: Int, isAppleSilicon: Bool,
    hasEntitlement: Bool, modelReason: AICapabilityReason) -> AICapability {
    guard isAppleSilicon else {
      return AICapability(available: false, message: "Apple Intelligence requires Apple Silicon.", reason: .deviceNotEligible)
    }
    guard majorVersion >= 27 else {
      return AICapability(available: false,
        message: "Private Cloud Compute text planning requires macOS 27 or later.", reason: .unsupportedSystem)
    }
    guard hasEntitlement else {
      return AICapability(available: false,
        message: "This build is not signed for Private Cloud Compute text planning. Use an Apple-approved PCC-enabled build.",
        reason: .missingEntitlement)
    }
    switch modelReason {
    case .ready:
      return AICapability(available: true,
        message: "Apple's Private Cloud Compute language model is ready. Your instruction is sent to Apple's service. No image pixels are sent.")
    case .deviceNotEligible:
      return AICapability(available: false, message: "This Mac is not eligible for Apple Intelligence.", reason: modelReason)
    case .systemNotReady:
      return AICapability(available: false,
        message: "Apple's Private Cloud Compute service is not ready. Check Apple Intelligence in System Settings and try again later.", reason: modelReason)
    case .frameworkUnavailable:
      return AICapability(available: false, message: "Private Cloud Compute text planning is unavailable on this system.", reason: modelReason)
    default:
      return AICapability(available: false, message: "Apple's Private Cloud Compute language model is unavailable.", reason: .unknown)
    }
  }

  public static var privateCloudComputeCapability: AICapability {
    let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    #if arch(arm64)
    let arm = true
    #else
    let arm = false
    #endif
    let entitled = privateCloudComputeEntitled
    func capability(_ reason: AICapabilityReason) -> AICapability {
      cloudTextCapability(majorVersion: major, isAppleSilicon: arm,
        hasEntitlement: entitled, modelReason: reason)
    }
    let admission = capability(.ready)
    guard admission.available else { return admission }
    #if canImport(FoundationModels)
    if #available(macOS 27.0, *) {
      switch PrivateCloudComputeLanguageModel().availability {
      case .available: return admission
      case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible: return capability(.deviceNotEligible)
        case .systemNotReady: return capability(.systemNotReady)
        @unknown default: return capability(.unknown)
        }
      @unknown default: return capability(.unknown)
      }
    }
    #endif
    return capability(.frameworkUnavailable)
  }
}
