import Foundation

extension PatternArchive {
  private struct LibraryEnvelope: Codable {
    let version: Int
    let state: PatternLibraryState
  }
  private struct LibraryVersion: Decodable { let version: Int }
  public static func encodeLibraryState(_ state:PatternLibraryState)throws->Data {
    try state.validate()
    let encoder=PropertyListEncoder();encoder.outputFormat = .binary
    let data=try encoder.encode(LibraryEnvelope(version:PatternLibraryState.version,state:state))
    guard data.count<=maxBytes else{throw CraftError.invalid("Pattern library file is too large.")}
    return data
  }
  public static func libraryVersion(_ data:Data)throws->Int {
    guard data.count<=maxBytes else{throw CraftError.invalid("Pattern library file is too large.")}
    return try PropertyListDecoder().decode(LibraryVersion.self,from:data).version
  }
  public static func decodeLibraryState(_ data:Data)throws->PatternLibraryState {
    switch try libraryVersion(data) {
    case 1:
      let old=try decodeState(data)
      let state=PatternLibraryState(patterns:old.patterns,selectedID:old.selectedID)
      try state.validate();return state
    case PatternLibraryState.version:
      let decoder=PropertyListDecoder()
      decoder.userInfo[.rasterDecodeBudget]=RasterDecodeBudget(bytes:1024*1024*1024)
      var state=try decoder.decode(LibraryEnvelope.self,from:data).state
      try state.validate();state.nodes=try state.orderedNodes();return state
    default:throw CraftError.unsupported("Unknown pattern library version.")
    }
  }
}
