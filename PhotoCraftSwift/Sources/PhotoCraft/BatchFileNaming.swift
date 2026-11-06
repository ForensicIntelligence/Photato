import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct BatchFileNaming: Codable, Equatable, Sendable {
  enum Kind: String, Codable, CaseIterable, Sendable {
    case documentName, documentLower, documentUpper, extensionLower, extensionUpper
    case serial1, serial2, serial3, serial4, letterLower, letterUpper
    case ddmm, ddmmyy, mmdd, mmddyy, yyddmm, yymmdd, yyyymmdd, literal
    var title: String { switch self {
      case .documentName:"Document Name";case .documentLower:"document name";case .documentUpper:"DOCUMENT NAME"
      case .extensionLower:"extension";case .extensionUpper:"EXTENSION"
      case .serial1:"1 Digit Serial Number";case .serial2:"2 Digit Serial Number";case .serial3:"3 Digit Serial Number";case .serial4:"4 Digit Serial Number"
      case .letterLower:"Serial Letter (a, b, c…)";case .letterUpper:"Serial Letter (A, B, C…)"
      case .ddmm:"ddmm (Day, Month)";case .ddmmyy:"ddmmyy (Day, Month, Year)"
      case .mmdd:"mmdd (Month, Day)";case .mmddyy:"mmddyy (Month, Day, Year)"
      case .yyddmm:"yyddmm (Year, Day, Month)";case .yymmdd:"yymmdd (Year, Month, Day)"
      case .yyyymmdd:"yyyymmdd (Full Year, Month, Day)";case .literal:"Custom Text"
    }}
    var identifiesSource: Bool { switch self {
      case .documentName,.documentLower,.documentUpper,.serial1,.serial2,.serial3,.serial4,.letterLower,.letterUpper:true
      default:false
    }}
  }
  struct Element: Codable, Equatable, Identifiable, Sendable {
    var id=UUID()
    enum CodingKeys:String,CodingKey {case kind,text}
    static func ==(a:Self,b:Self)->Bool {a.kind==b.kind && a.text==b.text}
    var kind: Kind
    var text: String = ""
  }
  var elements: [Element] = [.init(kind:.documentName),.init(kind:.extensionLower)]
  var startingSerial: Int = 1
  var windows = true
  var macOS = true
  var unix = true
  var date = Date()
  var timeZone = TimeZone.current.identifier
  static let maximumSerial = 9_007_199_254_740_735 // Remains exact in API JSON, including256source offsets.
  private static let locale = Locale(identifier:"en_US_POSIX")
  func validate() throws {
    guard (1...6).contains(elements.count),elements.contains(where:{$0.kind.identifiesSource}),
      (0...Self.maximumSerial).contains(startingSerial),date.timeIntervalSince1970.isFinite,
      let zone=TimeZone(identifier:timeZone) else {throw CraftError.invalid("Choose 1–6 naming fields, including a document name or serial, with a valid starting number, date and time zone.")}
    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
    guard (1900...9999).contains(calendar.component(.year,from:date)) else {throw CraftError.invalid("The naming date must have a Gregorian year from 1900 to 9999.")}
    for field in elements {
      guard field.text.utf8.count<=128,!field.text.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}),
        field.kind == .literal || field.text.isEmpty else {throw CraftError.invalid("Custom text supports up to 128 UTF-8 bytes and cannot contain controls. Other naming fields do not use text.")}
    }
  }
  func filename(source: String,index: Int,format:DocumentIO.Format) throws -> String {
    try validate();guard (0..<256).contains(index) else{throw CraftError.invalid("Batch index exceeds the 256-source limit.")}
    let name=source.precomposedStringWithCanonicalMapping
    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:timeZone)!
    let parts=calendar.dateComponents([.year,.month,.day],from:date),y=parts.year!,m=parts.month!,d=parts.day!
    func two(_ n:Int)->String {String(format:"%02d",n)}
    var result=""
    for field in elements {
      switch field.kind {
      case .documentName:result+=name
      case .documentLower:result+=name.lowercased(with:Self.locale)
      case .documentUpper:result+=name.uppercased(with:Self.locale)
      case .extensionLower:result+="."+format.rawValue.lowercased(with:Self.locale)
      case .extensionUpper:result+="."+format.rawValue.uppercased(with:Self.locale)
      case .serial1,.serial2,.serial3,.serial4:
        let digits = field.kind == .serial1 ? 1:field.kind == .serial2 ? 2:field.kind == .serial3 ? 3:4
        let value=String(startingSerial+index);result+=String(repeating:"0",count:max(0,digits-value.count))+value
      case .letterLower,.letterUpper:
        var value=index+1,text=""
        while value>0 {value-=1;text=String(UnicodeScalar(65+value%26)!)+text;value/=26}
        result+=field.kind == .letterUpper ? text:text.lowercased(with:Self.locale)
      case .ddmm:result+=two(d)+two(m)
      case .ddmmyy:result+=two(d)+two(m)+two(y%100)
      case .mmdd:result+=two(m)+two(d)
      case .mmddyy:result+=two(m)+two(d)+two(y%100)
      case .yyddmm:result+=two(y%100)+two(d)+two(m)
      case .yymmdd:result+=two(y%100)+two(m)+two(d)
      case .yyyymmdd:result+=String(format:"%04d",y)+two(m)+two(d)
      case .literal:result+=field.text
      }
    }
    result=result.precomposedStringWithCanonicalMapping
    guard !result.isEmpty,result != ".",result != "..",result.utf8.count<=255,
      !result.contains("/"),!result.contains("\\"),!result.contains(":"),
      !result.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}) else {throw CraftError.invalid("Generated names must be safe single filenames of at most 255 UTF-8 bytes.")}
    if windows {
      let stem=String(result.split(separator:".",omittingEmptySubsequences:false).first ?? "").trimmingCharacters(in:CharacterSet(charactersIn:" .")).uppercased(with:Self.locale)
      let reserved=["CON","PRN","AUX","NUL"]+(1...9).flatMap{["COM\($0)","LPT\($0)"]}+["COM¹","COM²","COM³","LPT¹","LPT²","LPT³"]
      guard !result.contains(where:{"<>\"|?*".contains($0)}),!result.hasSuffix("."),!result.hasSuffix(" "),!reserved.contains(stem) else {throw CraftError.invalid("Generated name is not Windows compatible.")}
    }
    return result
  }
  func collisionKey(_ name:String)->String {
    let normalized=name.precomposedStringWithCanonicalMapping
    return windows || macOS ? normalized.folding(options:.caseInsensitive,locale:Self.locale):normalized
  }
  func plan(sources:[String],format:DocumentIO.Format)throws->[String] {
    try validate();guard (1...256).contains(sources.count)else{throw CraftError.invalid("Choose 1–256 batch sources.")}
    let names=try sources.enumerated().map{try filename(source:$0.element,index:$0.offset,format:format)}
    guard Set(names.map(collisionKey)).count==names.count else {throw CraftError.invalid("The naming fields produce duplicate filenames. Add a serial field or change the source names.")}
    return names
  }
  func validateAvailable(_ name:String,in directory:URL)throws {
    // Best-effort compatibility alias check; atomic link remains authoritative for
    // the actual filesystem name. No all-files or cross-platform race guarantee.
    let names=try FileManager.default.contentsOfDirectory(atPath:directory.path)
    guard !names.contains(where:{collisionKey($0)==collisionKey(name)}) else {throw CraftError.invalid("An output with this compatible filename already exists.")}
  }
}
