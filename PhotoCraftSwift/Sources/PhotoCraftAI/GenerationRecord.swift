import Foundation

/// Descriptive provenance for an image accepted from the system interface.
/// This is not provider attestation. The interface does not expose a model ID,
/// seed or the final prompt after the user edits concepts inside the system UI.
public struct GenerationRecord:Codable,Equatable,Sendable {
  public enum Processing:String,Codable,Sendable {case onDevice,privateCloudCompute,unknown}
  public let version:Int
  public let requestID:UUID
  public let sourceDocumentID:UUID
  public let sourceRevision:UUID
  public let initialPrompt:String
  public let startedAt:Date
  public let acceptedAt:Date
  public let processing:Processing
  public let resultStyle:String?
  public let originalMediaType:String
  public let originalSHA256:String
  public let originalByteCount:Int
  public var provider:String {"Apple Image Playground"}
  public var modelIdentifier:String? {nil}
  public var seed:String? {nil}
  public var finalPrompt:String? {nil}
  public var isProviderAttestation:Bool {false}
  public static let maximumOriginalBytes=32*1024*1024
  public static let maximumRecordBytes=16*1024

  public init(requestID:UUID,sourceDocumentID:UUID,sourceRevision:UUID,
    initialPrompt:String,startedAt:Date,acceptedAt:Date,processing:Processing,
    resultStyle:String?,originalMediaType:String,originalSHA256:String,originalByteCount:Int)throws {
    version=1;self.requestID=requestID;self.sourceDocumentID=sourceDocumentID;self.sourceRevision=sourceRevision
    self.initialPrompt=initialPrompt;self.startedAt=startedAt;self.acceptedAt=acceptedAt;self.processing=processing
    self.resultStyle=resultStyle;self.originalMediaType=originalMediaType;self.originalSHA256=originalSHA256;self.originalByteCount=originalByteCount
    try validate()
  }
  public func validate()throws {
    guard version==1,try LocalAI.validatePrompt(initialPrompt)==initialPrompt,
      startedAt.timeIntervalSinceReferenceDate.isFinite,acceptedAt.timeIntervalSinceReferenceDate.isFinite,
      resultStyle.map({!$0.isEmpty && $0.utf8.count<=256}) ?? true,
      ["image/png","image/jpeg","image/tiff","image/heic","image/x-exr"].contains(originalMediaType),
      originalSHA256.utf8.count==64,originalSHA256.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),
      (1...Self.maximumOriginalBytes).contains(originalByteCount)
    else {throw RecordError.invalid}
  }
  public func encoded()throws->Data {
    try validate();let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let data=try encoder.encode(self)
    guard data.count<=Self.maximumRecordBytes else{throw RecordError.invalid};return data
  }
  public static func decode(_ data:Data)throws->Self {
    guard data.count<=maximumRecordBytes else{throw RecordError.invalid}
    let value=try JSONDecoder().decode(Self.self,from:data);try value.validate();return value
  }
  public enum RecordError:LocalizedError,Sendable {
    case invalid
    public var errorDescription:String? {"The image generation record is invalid or exceeds its storage limits."}
  }
}
