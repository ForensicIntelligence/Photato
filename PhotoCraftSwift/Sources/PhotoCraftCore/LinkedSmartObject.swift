import CryptoKit
import Foundation

/// Declarative external reference. Decoding never opens a file or performs I/O.
/// Native authorization lives in the app's private grant registry, not this file.
public struct LinkedSmartObjectSource:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,Sendable {case file,remote}
  public var kind:Kind
  public var reference:String
  public var relativePath: String?
  public var authorizationID:UUID?
  public var contentHash:String?
  public var byteLength:UInt64
  public var modificationDate:Date?
  public init(reference:String,kind:Kind = .file,authorizationID:UUID? = nil,
    contentHash:String? = nil,byteLength:UInt64,modificationDate:Date? = nil,
    relativePath: String? = nil)throws {
    self.kind=kind;self.reference=reference;self.authorizationID=authorizationID
    self.contentHash=contentHash;self.byteLength=byteLength;self.modificationDate=modificationDate
    self.relativePath = relativePath
    try validate()
  }
  /// A relative hint may traverse parent directories in the interchange format.
  /// The desktop resolver separately limits a folder approval to its own descendants.
  public static func isRelativePath(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 16384 && !value.hasPrefix("/") && !value.hasPrefix("\\")
      && !value.contains(":") && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }
  public func validate()throws {
    guard !reference.isEmpty,reference.utf8.count<=16384,!reference.contains("\0"),
      !reference.contains("\n"),!reference.contains("\r"),byteLength<=UInt64(Int64.max),
      modificationDate.map({$0.timeIntervalSince1970.isFinite}) ?? true else{throw CraftError.invalid("Invalid linked Smart Object reference.")}
    if let hash=contentHash {
      guard hash.utf8.count==64,hash.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{throw CraftError.invalid("Invalid linked source fingerprint.")}
    }
    if let relativePath {
      guard kind == .file, Self.isRelativePath(relativePath) else {
        throw CraftError.invalid("Invalid relative linked Smart Object path.")
      }
    }
    if kind == .remote {
      guard let url=URL(string:reference),["http","https"].contains(url.scheme?.lowercased() ?? ""),url.host != nil,
        url.user==nil,url.password==nil,url.query==nil,url.fragment==nil,authorizationID==nil else{throw CraftError.invalid("Remote link references must omit credentials, queries and fragments.")}
    }
  }
  public static func fingerprint(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
  /// Resource-job locators never archive presigned credentials.
  public static func remote(_ url:URL,data:Data)throws->Self {
    guard var fields=URLComponents(url:url,resolvingAgainstBaseURL:false) else{throw CraftError.invalid("Invalid linked resource URL.")}
    fields.user=nil;fields.password=nil;fields.query=nil;fields.fragment=nil
    guard let reference=fields.url?.absoluteString else{throw CraftError.invalid("Invalid linked resource URL.")}
    return try .init(reference:reference,kind:.remote,contentHash:fingerprint(data),byteLength:UInt64(data.count))
  }
}

extension SmartObject {
  public func linked(to reference:LinkedSmartObjectSource)throws->SmartObject {
    try validate();try reference.validate()
    guard !data.isEmpty,reference.contentHash==dataFingerprint,reference.byteLength==UInt64(data.count) else{throw CraftError.invalid("Link metadata must match the retained source bytes.")}
    var result=self;result.linkedSource=reference;try result.validate();return result
  }
  public func embedding()throws->SmartObject {
    guard linkedSource != nil,!data.isEmpty else{throw CraftError.invalid("Resolve the linked source before embedding it.")}
    var result=self;result.linkedSource=nil;try result.validate();return result
  }
  /// Runtime source hydration does not change document pixels, identity or revision.
  public func hydrating(_ bytes:Data)throws->SmartObject {
    try hydrating(.memory(bytes))
  }
  public func hydrating(_ source: EmbeddedSourceBytes) throws -> SmartObject {
    let bytes = source.data
    let limit = source.isFileBacked ? Self.maximumLocalEmbeddedBytes(forHeader: bytes) : Self.maximumSourceBytes
    guard let link = linkedSource, let digest = link.contentHash,
      bytes.count <= limit, UInt64(bytes.count) == link.byteLength,
      source.fingerprint == digest else {
      throw CraftError.invalid("The linked source changed; update its contents first.")
    }
    var value = self
    value.retainVerifiedOriginal(source, digest: digest)
    try value.validate()
    return value
  }
}

/// Prepared, immutable linked-source edits keep file I/O outside the Core engine.
/// A reference payload avoids increasing every primitive Command stack frame.
public final class LinkedSmartObjectEdit:Sendable {
  public let source:CraftDocument
  public let result:CraftDocument
  public let title:String
  public init(source:CraftDocument,result:CraftDocument,title:String)throws {
    guard source.id==result.id else{throw CraftError.invalid("Linked source edit changed document identity.")}
    try result.validate();self.source=source;self.result=result;self.title=title
  }
  public func applied(to document:CraftDocument)throws->CraftDocument {
    try Task.checkCancellation();guard document==source else{throw CraftError.invalid("The document changed while preparing linked artwork.")}
    try result.validate();return result
  }
}

/// An unresolved PSD stores a transformed layer preview, not original source pixels.
/// Keep that cache exact until authorization lets us replace it with source pixels.
public struct LinkedSmartObjectPreview:Codable,Equatable,Sendable {
  public var sourceToCache:Transform2D
  public var sourceWidth:Int
  public var sourceHeight:Int
  public var cacheWidth:Int
  public var cacheHeight:Int
  public init(sourceToCache:Transform2D,sourceWidth:Int,sourceHeight:Int,cacheWidth:Int,cacheHeight:Int)throws {
    self.sourceToCache=sourceToCache;self.sourceWidth=sourceWidth;self.sourceHeight=sourceHeight
    self.cacheWidth=cacheWidth;self.cacheHeight=cacheHeight;try validate()
  }
  public func validate()throws {
    try sourceToCache.validated()
    guard [sourceWidth,sourceHeight,cacheWidth,cacheHeight].allSatisfy({(1...Surface.maxDimension).contains($0)}) else{throw CraftError.invalid("Invalid linked preview dimensions.")}
  }
}
extension Layer {
  public func linkedSmartObjectPreview()throws->LinkedSmartObjectPreview? {
    guard let data=sourceTags?["PhLC"] else{return nil}
    guard data.count<=4096 else{throw CraftError.invalid("Invalid linked preview metadata.")}
    let value=try JSONDecoder().decode(LinkedSmartObjectPreview.self,from:data);try value.validate();return value
  }
  public mutating func setLinkedSmartObjectPreview(_ value:LinkedSmartObjectPreview?)throws {
    guard let value else{sourceTags?.removeValue(forKey:"PhLC");return}
    try value.validate();if sourceTags==nil{sourceTags=[:]}
    let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys;sourceTags?["PhLC"]=try encoder.encode(value)
  }
  public func smartObjectSourceTransform()throws->Transform2D {
    try linkedSmartObjectPreview().map{coordinateTransform * $0.sourceToCache} ?? coordinateTransform
  }
  public func smartObjectSourceProjection() throws -> ProjectiveTransform? {
    try sourceProjection?.followed(by: coordinateTransform)
  }
}
