import Foundation
import XCTest
@testable import PhotoCraftCore

final class VariableDataImportTests: XCTestCase {
  func testQuotedMultilineUnicodeSpacesEscapesAndBothDelimiters() throws {
    XCTAssertEqual(try VariableDataImport.table("\u{feff}name, text\r\n Café , \"  line 1\nline \"\"2\"\"  \"\r\n", delimiter: .comma), [["name", "text"], ["Café", "  line 1\nline \"2\"  "]])
    XCTAssertEqual(try VariableDataImport.table("a\tb\rc\t\"x\ty\"\r", delimiter: .tab), [["a", "b"], ["c", "x\ty"]])
    XCTAssertEqual(try VariableDataImport.table("title\n\"\"\n", delimiter: .comma), [["title"], [""]])
    for value in ["a,b\n1", "a\n\"missing", "a\nx\"bad", "a\n\"x\"bad", "a,b\n1,2,3", "", "a\n"] {
      XCTAssertThrowsError(try VariableDataImport.table(value, delimiter: .comma), value)
    }
  }
  func testImportEveryVariableNamedRowsAndResolver() throws {
    let vars = try VariablesTests().template().variables!
    let imageID = UUID(); var resolved: [String] = []
    var options = VariableDataImportOptions(); options.firstColumnNames = true
    let rows = try VariableDataImport.dataSets("title,photo,show\n\"First, hello\",images/one.png,true\nSecond,images/two.png,false\n", variables: vars, options: options) { path in resolved.append(path); return imageID }
    XCTAssertEqual(rows.map(\.name), ["First, hello", "Second"])
    XCTAssertEqual(rows[0].values["title"], .text("First, hello"))
    XCTAssertEqual(rows[1].values["show"], .visibility(false))
    XCTAssertEqual(rows[0].values["photo"], .pixels(imageID))
    XCTAssertEqual(resolved, ["images/one.png", "images/two.png"])
    let extensionRows = try VariableDataImport.dataSets("DataSet,title,show,photo\nBanner,Welcome,true,a.png", variables: vars, options: options) { _ in imageID }
    XCTAssertEqual(extensionRows[0].name, "Banner"); XCTAssertEqual(extensionRows[0].values["title"], .text("Welcome"))
  }
  func testUnknownMissingDuplicateAndIncorrectValuesReject() throws {
    let vars = try VariablesTests().template().variables!
    for csv in ["title,show\na,true", "title,show,photo,unknown\na,true,x,y", "title,title,photo\na,a,x", "title,show,photo\na,1,x", "title,show,photo\na,true,", "title,show,photo\na,TRUE,x"] {
      XCTAssertThrowsError(try VariableDataImport.dataSets(csv, variables: vars) { _ in UUID() })
    }
    XCTAssertThrowsError(try VariableDataImport.dataSets("title,show,photo\na,true,x", variables: vars) { _ in throw CraftError.invalid("Missing source") })
    var options = VariableDataImportOptions(); options.firstColumnNames = true
    XCTAssertThrowsError(try VariableDataImport.dataSets("title,show,photo\nsame,true,x\nsame,false,y", variables: vars, options: options) { _ in UUID() })
  }
}
