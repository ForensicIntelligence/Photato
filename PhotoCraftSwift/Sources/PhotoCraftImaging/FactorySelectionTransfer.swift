import Foundation
import CryptoKit
import zlib
import PhotoCraftCore

/// Precompiled standard-profile RGB8 transform measured from owned numerical
/// input through the reference UI. All2^24 input colors were checked, including
/// identical colors at different positions and embedded/untagged sources.
/// Other profile pairs keep the general ICC transform; no fixture/test identity
/// participates in dispatch. See docs/SELECTION_LUMINOSITY.md for provenance.
enum FactorySelectionTransfer {
  static let entries=1<<24
  static let rawSHA="4518de76c475009c7875918b6544d3f153e407d7974fde399d0c4cf0f47005b4"
  static let compressedSHA="a0cada1e6af7bbb4c10532e45e220211e1991c0d59c6cc69616e3127465a5d91"
  static let compressedBytes=1336408
  static let rgbSHA="fea1ce51d4f64650bdb17e80c2120f30b28ac038320751fe5d1267000e22788e",graySHA="2905bbfb8f112edbf37b3c3a5f2695e2a6dbc9f601d202b4c0523a93a9ae6bd2"
  static var resourceURL:URL? {
    #if SWIFT_PACKAGE
    if let root=Bundle.main.resourceURL,
      let bundle=Bundle(url:root.appendingPathComponent("Photato_PhotoCraftImaging.bundle")),
      let url=bundle.url(forResource:"FactoryRGB8Gray20",withExtension:"zlib") {return url}
    // A packaged app must not borrow a resource from a developer build path.
    if Bundle.main.bundleURL.pathExtension == "app",Bundle.main.executableURL?.lastPathComponent == "Photato" {return nil}
    return Bundle.module.url(forResource:"FactoryRGB8Gray20",withExtension:"zlib")
    #else
    return Bundle.main.url(forResource:"FactoryRGB8Gray20",withExtension:"zlib")
    #endif
  }
  static let shared:Result<Data,Error> = Result {
    guard let url=resourceURL else{throw CraftError.unsupported("The bundled standard RGB8 selection transform is missing.")}
    return try load(url)
  }
  static func sha(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
  static func load(_ url:URL)throws->Data {
    let compressed=try Data(contentsOf:url,options:.mappedIfSafe)
    // Verify trusted compressed bytes before inflation, then verify the full
    // output. A missing/corrupt table never silently changes color arithmetic.
    guard compressed.count==compressedBytes,sha(compressed)==compressedSHA else{throw CraftError.invalid("The standard selection transform failed its integrity check.")}
    var bytes=Data(count:entries),length=uLongf(entries),consumed=uLong(compressed.count)
    let status=bytes.withUnsafeMutableBytes {target in compressed.withUnsafeBytes {source in
      uncompress2(target.bindMemory(to:UInt8.self).baseAddress!,&length,source.bindMemory(to:UInt8.self).baseAddress!,&consumed)
    }}
    guard status==Z_OK,length==entries,consumed==compressed.count else{throw CraftError.invalid("Invalid compressed standard selection transform.")}
    guard bytes.count==entries,sha(bytes)==rawSHA else{throw CraftError.invalid("Invalid standard selection transform coverage.")}
    return bytes
  }
  static func signature(_ data:Data,mode:DocumentColorMode,keys:[String])throws->String? {
    let profile:ICCSelectionMatrix.Profile
    do {profile=try .init(data,mode:mode)}catch ICCSelectionMatrix.Unrepresented.profile{return nil}
    var hash=SHA256()
    for key in keys {
      guard let range=profile.tags[key]else{return nil}
      hash.update(data:Data(key.utf8));var size=UInt32(range.count).bigEndian
      withUnsafeBytes(of:&size){hash.update(bufferPointer:$0)}
      hash.update(data:data.subdata(in:range))
    }
    return hash.finalize().map{String(format:"%02x",$0)}.joined()
  }
  static func supports(_ document:CraftDocument,settings:ColorSettings,source:Data,gray:Data)throws->Bool {
    guard document.colorMode == .rgb,document.depth == .u8,settings.intent == .relativeColorimetric,settings.blackPointCompensation else{return false}
    let rgbDefault=document.workingICC == nil && document.modeDescriptor == nil
    guard try rgbDefault || signature(source,mode:.rgb,keys:["rXYZ","gXYZ","bXYZ","rTRC","gTRC","bTRC","wtpt","bkpt"])==rgbSHA else{return false}
    return try settings.workingGray == nil || signature(gray,mode:.grayscale,keys:["wtpt","bkpt","kTRC"])==graySHA
  }
  static func coverage(_ pixel:Pixel,table:Data)->Float {
    let r=Int((unit(pixel.r)*255).rounded()),g=Int((unit(pixel.g)*255).rounded()),b=Int((unit(pixel.b)*255).rounded())
    return Float(table[(r<<16)|(g<<8)|b])/255
  }
}
