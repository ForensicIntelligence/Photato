import Foundation
import XCTest
@testable import PhotoCraftAI

final class ParameterizedEditPlanTests: XCTestCase {
  func testLegacyAndMixedPlansRoundTripWithoutDiscardingValues() throws {
    let legacy = Data(#"{"summary":"Owned legacy","operations":["autoTone","autoContrast","autoColor","desaturate","invert"]}"#.utf8)
    let old = try NativeEditPlan.decode(legacy)
    XCTAssertEqual(old.operations, NativeEditOperation.allCases)
    let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    XCTAssertEqual(encoded["operations"] as? [String], ["autoTone", "autoContrast", "autoColor", "desaturate", "invert"])
    let mixed = try NativeEditPlan.decode(Data(#"{"summary":"One stop then less colour","operations":[{"operation":"exposure","parameters":{"exposure":1,"offset":0,"gammaCorrection":1}},"invert",{"operation":"vibrance","parameters":{"vibrance":-25,"saturation":-10}}]}"#.utf8))
    XCTAssertEqual(try NativeEditPlan.decode(JSONEncoder().encode(mixed)), mixed)
    XCTAssertEqual(mixed.operations.map(\.rawValue), ["exposure", "invert", "vibrance"])
    XCTAssertTrue(mixed.operations[0].title.contains("Exposure 1 EV"))
    XCTAssertTrue(mixed.operations[0].title.contains("Offset 0"))
    XCTAssertTrue(mixed.operations[0].title.contains("Gamma Correction 1"))
    XCTAssertTrue(mixed.operations[2].title.contains("Saturation -10 %"))
  }
  func testObjectOperationsRejectMissingUnknownBooleanFractionalAndUnboundedValues() throws {
    let invalid = [
      #"{"operation":"exposure","parameters":{"exposure":1,"offset":0}}"#,
      #"{"operation":"exposure","parameters":{"exposure":1,"offset":0,"gammaCorrection":1,"path":"/tmp/x"}}"#,
      #"{"operation":"exposure","parameters":{"exposure":true,"offset":0,"gammaCorrection":1}}"#,
      #"{"operation":"exposure","parameters":{"exposure":21,"offset":0,"gammaCorrection":1}}"#,
      #"{"operation":"exposure","parameters":{"exposure":0,"offset":null,"gammaCorrection":1}}"#,
      #"{"operation":"exposure","parameters":{"exposure":0,"offset":0,"gammaCorrection":1},"target":"other"}"#,
      #"{"operation":"hueSaturation","parameters":{"hue":0.5,"saturation":0,"lightness":0}}"#,
      #"{"operation":"hueSaturation","parameters":{"hue":0,"saturation":0,"lightness":0,"colorize":1}}"#,
      #"{"operation":"brightnessContrast","parameters":{"brightness":0,"contrast":0,"legacy":0}}"#,
      #"{"operation":"vibrance","parameters":{"vibrance":0,"saturation":101}}"#,
      #"{"operation":"evalScript","parameters":{}}"#,
      #"{"operation":"invert","parameters":{}}"#, #""exposure""#,
      #"{"operation":"exposure","parameters":{"exposure":1e100,"offset":0,"gammaCorrection":1}}"#
    ]
    for operation in invalid {
      let json = "{\"summary\":\"Owned invalid\",\"operations\":[" + operation + "]}"
      XCTAssertThrowsError(try NativeEditPlan.decode(Data(json.utf8)), operation)
    }
  }
  func testEveryAdjustmentBoundaryAndNeutralAndInvalidNumberIsChecked() throws {
    for kind in NativeEditAdjustment.Kind.allCases {
      let neutral = Dictionary(uniqueKeysWithValues: kind.parameters.map { ($0.name, $0.neutral) })
      for parameter in kind.parameters {
        for boundary in [parameter.minimum, parameter.maximum] {
          var values = neutral; values[parameter.name] = boundary
          let value = try NativeEditAdjustment(kind, parameters: values)
          XCTAssertEqual(try JSONDecoder().decode(NativeEditAdjustment.self, from: JSONEncoder().encode(value)), value)
        }
        for invalid in [parameter.minimum - 1, parameter.maximum + 1, .infinity, -.infinity, .nan] {
          var values = neutral; values[parameter.name] = invalid
          XCTAssertThrowsError(try NativeEditAdjustment(kind, parameters: values))
        }
        if parameter.integer {
          var values = neutral; values[parameter.name] = 0.25
          XCTAssertThrowsError(try NativeEditAdjustment(kind, parameters: values))
        }
      }
    }
  }
  func testValidatedModelOperationCannotInventParametersOrTargets() throws {
    for operation in NativeEditOperation.allCases {
      XCTAssertEqual(try NativeEditOperation(name: operation.rawValue, parameters: [:]), operation)
      XCTAssertThrowsError(try NativeEditOperation(name: operation.rawValue, parameters: ["target": 1]))
    }
    for kind in NativeEditAdjustment.Kind.allCases {
      let values = Dictionary(uniqueKeysWithValues: kind.parameters.map { ($0.name, $0.neutral) })
      XCTAssertEqual(try NativeEditOperation(name: kind.rawValue, parameters: values), .adjustment(try .init(kind, parameters: values)))
    }
    XCTAssertThrowsError(try NativeEditOperation(name: "openFile", parameters: [:]))
    XCTAssertEqual(Set(NativeEditOperation.supportedNames).count, 9)
  }
}
