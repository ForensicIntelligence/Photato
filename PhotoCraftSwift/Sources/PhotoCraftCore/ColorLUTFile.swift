import Foundation

/// Bounded native Cube, Autodesk3DL and SpeedGrade LOOK transport.
public enum ColorLUTFile {
  public static let extensions = ["cube","3dl","look"]
  public static func read(_ data: Data, name: String) throws -> ColorLUT {
    guard data.count <= ColorLUT.maximumFileBytes, let text = String(data:data,encoding:.utf8) else { throw CraftError.invalid("LUT must be UTF-8 within64MiB.") }
    let filename = URL(fileURLWithPath:name).lastPathComponent
    let ext = URL(fileURLWithPath:filename).pathExtension.lowercased()
    var lut: ColorLUT
    switch ext {
    case "cube": lut = try cube(text)
    case "3dl": lut = try threeDL(text)
    case "look":
      guard text.range(of:"<!DOCTYPE",options:.caseInsensitive) == nil, text.range(of:"<!ENTITY",options:.caseInsensitive) == nil else { throw CraftError.unsupported("LOOK documents with entity declarations are unsupported.") }
      lut = try look(data)
    default: throw CraftError.unsupported("Choose a .cube, .3dl or .look LUT file.")
    }
    if lut.title.isEmpty { lut.title = URL(fileURLWithPath:filename).deletingPathExtension().lastPathComponent }
    lut.sourceFile = filename; lut.sourceData = data
    try lut.validate(); return lut
  }
  /// Original bytes retain nonuniform3DL grids and imported file semantics.
  public static func export(_ lut: ColorLUT) throws -> (name: String, data: Data) {
    try lut.validate()
    if let name = lut.sourceFile, let data = lut.sourceData {
      var decoded = try read(data,name:name), expected = lut
      decoded.sourceFile = nil; decoded.sourceData = nil; decoded.title = ""
      expected.sourceFile = nil; expected.sourceData = nil; expected.title = ""
      if decoded == expected { return (name,data) }
    }
    return ((lut.title.isEmpty ? "Color Lookup" : lut.title)+".cube",try writeCube(lut))
  }
  static func lines(_ text: String) -> [Substring] { text.split(whereSeparator: \.isNewline) }
  static func clean(_ input: Substring) -> String {
    var quoted = false, escaped = false, output = ""
    for c in input {
      if c == "#" && !quoted { break }
      output.append(c)
      if c == "\"" && !escaped { quoted.toggle() }
      escaped = c == "\\" && !escaped
    }
    return output.trimmingCharacters(in:.whitespacesAndNewlines)
  }
  static func numbers(_ tokens: [Substring], count: Int? = nil, maximum: Float = 65504) throws -> [Float] {
    if let count, tokens.count != count { throw CraftError.invalid("Wrong number of LUT values.") }
    return try tokens.map {
      guard let n = Float($0), n.isFinite, abs(n) <= maximum else { throw CraftError.invalid("Invalid or non-finite LUT number.") }; return n
    }
  }
  static func cube(_ text: String) throws -> ColorLUT {
    var size3: Int?, size1: Int?, title = "", low: [Float]?, high: [Float]?, range3: [Float]?, range1: [Float]?
    var values = [Float](), seen = Set<String>()
    for (lineNumber,line) in lines(text).enumerated() {
      if lineNumber % 1024 == 0 { try Task.checkCancellation() }
      let line = clean(line); if line.isEmpty { continue }
      let tokens = line.split(whereSeparator: \.isWhitespace); let key = String(tokens[0])
      if Float(key) != nil || ["nan","inf","-inf","+inf"].contains(key.lowercased()) {
        values += try numbers(tokens,count:3)
        guard values.count <= ColorLUT.maximumSize*ColorLUT.maximumSize*ColorLUT.maximumSize*3+65536*3 else { throw CraftError.invalid("LUT table exceeds its size limit.") }; continue
      }
      guard values.isEmpty else { throw CraftError.invalid("LUT headers must precede table values.") }
      guard seen.insert(key).inserted else { throw CraftError.invalid("Duplicate LUT header: \(key).") }
      switch key {
      case "TITLE":
        let rest = String(line.dropFirst(5)).trimmingCharacters(in:.whitespaces)
        if rest.first == "\"" {
          guard let data = rest.data(using:.utf8), let parsed = try? JSONDecoder().decode(String.self,from:data) else { throw CraftError.invalid("Malformed LUT title.") }; title = parsed
        } else { title = rest }
      case "LUT_3D_SIZE","LUT_1D_SIZE":
        guard tokens.count == 2, let n = Int(tokens[1]), (2...(key == "LUT_3D_SIZE" ? ColorLUT.maximumSize : 65536)).contains(n) else { throw CraftError.invalid("Unsupported LUT size.") }
        if key == "LUT_3D_SIZE" { size3 = n } else { size1 = n }
      case "DOMAIN_MIN": low = try numbers(Array(tokens.dropFirst()),count:3)
      case "DOMAIN_MAX": high = try numbers(Array(tokens.dropFirst()),count:3)
      case "LUT_3D_INPUT_RANGE": range3 = try numbers(Array(tokens.dropFirst()),count:2)
      case "LUT_1D_INPUT_RANGE": range1 = try numbers(Array(tokens.dropFirst()),count:2)
      default: throw CraftError.unsupported("Unsupported Cube directive: \(key).")
      }
    }
    guard size3 != nil || size1 != nil, (low == nil) == (high == nil), !(range3 != nil && low != nil), range3 == nil || size3 != nil, range1 == nil || size1 != nil else { throw CraftError.invalid("Conflicting or incomplete Cube input domains.") }
    let n = size3 ?? 2, curveCount = (size1 ?? 0)*3, cubeCount = size3.map { $0*$0*$0*3 } ?? 0
    guard values.count == curveCount+cubeCount else { throw CraftError.invalid("Cube table length does not match its dimensions.") }
    var lut = try ColorLUT.identity(size:n); lut.title = title
    if size3 != nil {
      lut.values = Array(values.dropFirst(curveCount))
      lut.domainMin = range3.map { Array(repeating:$0[0],count:3) } ?? low ?? [0,0,0]
      lut.domainMax = range3.map { Array(repeating:$0[1],count:3) } ?? high ?? [1,1,1]
    }
    if size1 != nil {
      guard !(size3 == nil && range1 != nil && low != nil) else { throw CraftError.invalid("Conflicting 1D input domains.") }
      let curveLow: [Float] = range1.map { Array(repeating:$0[0],count:3) } ?? (size3 == nil ? low : nil) ?? [0,0,0]
      let curveHigh: [Float] = range1.map { Array(repeating:$0[1],count:3) } ?? (size3 == nil ? high : nil) ?? [1,1,1]
      lut.curve = .init(values:Array(values.prefix(curveCount)),minimum:curveLow,maximum:curveHigh)
    }
    try lut.validate(); return lut
  }
  static func threeDL(_ text: String) throws -> ColorLUT {
    var rows = [[Float]](), grid: [Float]?, outputBits: Int?
    for (lineNumber,line) in lines(text).enumerated() {
      if lineNumber % 1024 == 0 { try Task.checkCancellation() }
      let line = clean(line); if line.isEmpty { continue }
      let tokens = line.split(whereSeparator: \.isWhitespace)
      if tokens[0] == "3DMESH" { guard rows.isEmpty, tokens.count == 1 else { throw CraftError.invalid("Invalid3DMESH header.") }; continue }
      if tokens[0] == "Mesh" {
        guard rows.isEmpty, tokens.count == 3, let bits = Int(tokens[2]), [8,10,12,14,16].contains(bits) else { throw CraftError.invalid("Invalid3DL Mesh precision.") }; outputBits = bits; continue
      }
      let nums = try numbers(tokens,maximum:65535)
      guard nums.allSatisfy({ $0 >= 0 && $0.rounded() == $0 }) else { throw CraftError.invalid("3DL samples must be nonnegative integers.") }
      if grid == nil, rows.isEmpty, nums.count != 3 { grid = nums }
      else { guard nums.count == 3 else { throw CraftError.invalid("Invalid3DL data row.") }; rows.append(nums) }
      guard rows.count <= ColorLUT.maximumSize*ColorLUT.maximumSize*ColorLUT.maximumSize else { throw CraftError.invalid("3DL table exceeds the size limit.") }
    }
    let n = Int(pow(Double(rows.count),1.0/3).rounded())
    guard (2...ColorLUT.maximumSize).contains(n), n*n*n == rows.count else { throw CraftError.invalid("3DL rows do not form a cube.") }
    let maximum = rows.lazy.flatMap { $0 }.max() ?? 0
    let scale = outputBits.map { Float((1 << $0)-1) } ?? (maximum <= 1 ? 1 : [Float(1023),4095,16383,65535].first(where: { maximum <= $0 }) ?? 65535)
    guard maximum <= scale else { throw CraftError.invalid("3DL samples exceed declared precision.") }
    var lut = try ColorLUT.identity(size:n)
    for (i,row) in rows.enumerated() {
      let r = i/(n*n), g = (i/n)%n, b = i%n, index = ((b*n+g)*n+r)*3
      for c in 0..<3 { lut.values[index+c] = row[c]/scale }
    }
    if let grid {
      guard grid.count == n, let last = grid.last, last > 0 else { throw CraftError.invalid("3DL input grid size differs from its cube.") }
      lut.inputGrid = grid.map { $0/last }
    }
    try lut.validate(); return lut
  }
  private final class LookReader: NSObject, XMLParserDelegate {
    var stack = [String](), captures = [String:String](), current = "", failure: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String:String] = [:]) {
      stack.append(elementName.lowercased()); current = ""
      if stack.count > 32 { failure = "LOOK nesting exceeds limit."; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { current += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
      let key = elementName.lowercased()
      if ["size","data","title"].contains(key) {
        if captures[key] != nil { failure = "Duplicate LOOK field."; parser.abortParsing() }
        captures[key] = current.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"\""))
      }
      if !stack.isEmpty { stack.removeLast() }; current = ""
    }
  }
  static func look(_ data: Data) throws -> ColorLUT {
    let delegate = LookReader(), parser = XMLParser(data:data); parser.delegate = delegate; parser.shouldResolveExternalEntities = false
    guard parser.parse(), delegate.failure == nil, let rawSize = delegate.captures["size"], let n = Int(rawSize), (2...ColorLUT.maximumSize).contains(n), let hex = delegate.captures["data"] else { throw CraftError.invalid(delegate.failure ?? "Invalid LOOK XML or table size.") }
    let digits = hex.utf8.filter { ![9,10,13,32].contains($0) }, count = n*n*n
    guard digits.count == count*3*8 || digits.count == count*4*8 else { throw CraftError.invalid("LOOK table byte count does not match its dimensions.") }
    func nibble(_ c: UInt8) throws -> UInt32 {
      switch c { case 48...57: UInt32(c-48); case 65...70: UInt32(c-55); case 97...102: UInt32(c-87); default: throw CraftError.invalid("Invalid LOOK hexadecimal data.") }
    }
    let channels = digits.count/(count*8); var values = [Float](); values.reserveCapacity(count*3)
    for i in 0..<(digits.count/8) {
      if i % 1024 == 0 { try Task.checkCancellation() }
      var bits: UInt32 = 0
      for b in 0..<4 { bits |= try (nibble(digits[i*8+b*2])*16+nibble(digits[i*8+b*2+1])) << (8*b) }
      let f = Float(bitPattern:bits)
      guard f.isFinite else { throw CraftError.invalid("Non-finite LOOK sample.") }
      if i%channels < 3 { values.append(f) }
    }
    let lut = ColorLUT(title:delegate.captures["title"] ?? "",size:n,values:values); try lut.validate(); return lut
  }
  public static func writeCube(_ lut: ColorLUT) throws -> Data {
    try lut.validate()
    guard lut.inputGrid == nil else { throw CraftError.unsupported("A nonuniform3DL input grid must be retained in its original file format.") }
    var s = "TITLE \(String(decoding:try JSONEncoder().encode(lut.title),as:UTF8.self))\n"
    if let curve = lut.curve {
      guard Set(curve.minimum).count == 1, Set(curve.maximum).count == 1 else { throw CraftError.unsupported("Cube export of a combined shaper requires shared channel input domains.") }
      s += "LUT_1D_SIZE \(curve.values.count/3)\nLUT_1D_INPUT_RANGE \(curve.minimum[0]) \(curve.maximum[0])\n"
    }
    s += "LUT_3D_SIZE \(lut.size)\nDOMAIN_MIN \(lut.domainMin.map { String($0) }.joined(separator:" "))\nDOMAIN_MAX \(lut.domainMax.map { String($0) }.joined(separator:" "))\n"
    for rows in [lut.curve?.values ?? [],lut.values] {
      for i in stride(from:0,to:rows.count,by:3) {
        if i % 3072 == 0 { try Task.checkCancellation() }
        s += "\(rows[i]) \(rows[i+1]) \(rows[i+2])\n"
      }
    }
    guard s.utf8.count <= ColorLUT.maximumFileBytes else { throw CraftError.invalid("Encoded LUT exceeds64MiB.") }
    return Data(s.utf8)
  }
}
