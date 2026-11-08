import Darwin
import Foundation
import XCTest
@testable import PhotoCraftCore

final class AtomicStagingDirectoryTests:XCTestCase {
  private func paths()throws->(root:URL,target:URL,stage:URL) {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let destination=root.appendingPathComponent("destination"),stage=root.appendingPathComponent("staging")
    try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
    try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false)
    return(root,destination.appendingPathComponent("owned.data"),stage)
  }
  func testCrossDirectoryCommitPreservesExactBytesModeAndVisibility()throws {
    let p=try paths();defer{try? FileManager.default.removeItem(at:p.root)}
    let original=Data("previous".utf8),expected=Data("Replacement".utf8)
    try original.write(to:p.target)
    try FileManager.default.setAttributes([.posixPermissions:0o640],ofItemAtPath:p.target.path)
    XCTAssertEqual(p.target.withUnsafeFileSystemRepresentation{chflags($0!,UInt32(UF_HIDDEN))},0)
    let writer=try AtomicFileWriter(to:p.target,maximumBytes:64,stagingDirectory:p.stage)
    try writer.append(Data("replacement".utf8));try writer.patch(Data("R".utf8),at:0)
    XCTAssertEqual(try Data(contentsOf:p.target),original)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:p.stage.path).count,1)
    try writer.commit()
    XCTAssertTrue(writer.isPublished);XCTAssertTrue(writer.directorySynchronized)
    XCTAssertEqual(try Data(contentsOf:p.target),expected)
    XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:p.target.path)[.posixPermissions]as?NSNumber)?.intValue,0o640)
    XCTAssertEqual(try p.target.resourceValues(forKeys:[.isHiddenKey]).isHidden,true)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:p.stage.path).isEmpty)
  }
  func testFailedCrossDirectoryRenamePreservesDestinationAndUnrelatedStagingContent()throws {
    let p=try paths();defer{try? FileManager.default.removeItem(at:p.root)}
    let previous=Data("previous".utf8),unrelated=p.stage.appendingPathComponent("unrelated")
    try previous.write(to:p.target);try Data("retain".utf8).write(to:unrelated)
    var operations=AtomicFileWriter.Operations()
    operations.renameStaged={_,_,_,_ in errno=EACCES;return -1}
    let writer=try AtomicFileWriter(to:p.target,stagingDirectory:p.stage,operations:operations)
    try writer.append(Data("candidate".utf8));XCTAssertThrowsError(try writer.commit());writer.discard()
    XCTAssertFalse(writer.isPublished);XCTAssertEqual(try Data(contentsOf:p.target),previous)
    XCTAssertEqual(try Data(contentsOf:unrelated),Data("retain".utf8))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:p.stage.path),["unrelated"])
  }
  func testChangedDestinationOrReplacedStagedNameRejectsWithoutRemovingAnotherFile()throws {
    for changeTarget in [true,false] {
      let p=try paths();defer{try? FileManager.default.removeItem(at:p.root)}
      let previous=Data("previous".utf8),external=Data("external".utf8)
      try previous.write(to:p.target)
      let writer=try AtomicFileWriter(to:p.target,stagingDirectory:p.stage)
      try writer.append(Data("candidate".utf8))
      let staged=p.stage.appendingPathComponent(try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath:p.stage.path).first))
      try external.write(to:changeTarget ? p.target:staged,options:.atomic)
      XCTAssertThrowsError(try writer.commit());writer.discard()
      XCTAssertFalse(writer.isPublished)
      XCTAssertEqual(try Data(contentsOf:p.target),changeTarget ? external:previous)
      if changeTarget{XCTAssertFalse(FileManager.default.fileExists(atPath:staged.path))}
      else{XCTAssertEqual(try Data(contentsOf:staged),external)}
    }
  }
  func testReboundStagingFolderRejectsAndCleansOnlyItsOpenedDirectory()throws {
    let p=try paths();defer{try? FileManager.default.removeItem(at:p.root)}
    let previous=Data("previous".utf8);try previous.write(to:p.target)
    let writer=try AtomicFileWriter(to:p.target,stagingDirectory:p.stage)
    try writer.append(Data("candidate".utf8))
    let moved=p.root.appendingPathComponent("moved-staging")
    try FileManager.default.moveItem(at:p.stage,to:moved)
    try FileManager.default.createDirectory(at:p.stage,withIntermediateDirectories:false)
    let other=p.stage.appendingPathComponent("keep");try Data("retain".utf8).write(to:other)
    XCTAssertThrowsError(try writer.commit());writer.discard()
    XCTAssertEqual(try Data(contentsOf:p.target),previous)
    XCTAssertEqual(try Data(contentsOf:other),Data("retain".utf8))
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:moved.path).isEmpty)
  }
  func testCancellationAndPublishedDirectoryFailureRetainDifferentOwners()async throws {
    let p=try paths();defer{try? FileManager.default.removeItem(at:p.root)}
    let previous=Data("previous".utf8),candidate=Data("candidate".utf8)
    try previous.write(to:p.target)
    let cancelled=try await Task.detached {
      let writer=try AtomicFileWriter(to:p.target,stagingDirectory:p.stage)
      try writer.append(candidate);withUnsafeCurrentTask{$0?.cancel()}
      do{try writer.commit();return false}catch is CancellationError{writer.discard();return true}
    }.value
    XCTAssertTrue(cancelled);XCTAssertEqual(try Data(contentsOf:p.target),previous)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:p.stage.path).isEmpty)
    var operations=AtomicFileWriter.Operations()
    operations.synchronizeDirectory={_ in errno=EIO;return -1}
    let writer=try AtomicFileWriter(to:p.target,stagingDirectory:p.stage,operations:operations)
    try writer.append(candidate)
    XCTAssertThrowsError(try writer.commit()){XCTAssertNotNil($0 as?AtomicFileWriter.PublicationFailure)}
    writer.discard();XCTAssertTrue(writer.isPublished);XCTAssertFalse(writer.directorySynchronized)
    XCTAssertEqual(try Data(contentsOf:p.target),candidate)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:p.stage.path).isEmpty)
  }
  func testInvalidStagingAndCapacityRejectBeforeReplacingTheDestination()throws {
    let p=try paths();defer{try? FileManager.default.removeItem(at:p.root)}
    let previous=Data("previous".utf8);try previous.write(to:p.target)
    XCTAssertThrowsError(try AtomicFileWriter(to:p.target,stagingDirectory:p.target))
    XCTAssertThrowsError(try AtomicFileWriter(to:p.target,stagingDirectory:p.root.appendingPathComponent("missing")))
    XCTAssertThrowsError(try AtomicFileWriter(to:p.target,stagingDirectory:URL(string:"https://example.invalid/stage")!))
    let writer=try AtomicFileWriter(to:p.target,maximumBytes:2,stagingDirectory:p.stage)
    XCTAssertThrowsError(try writer.append(Data([1,2,3])));writer.discard()
    XCTAssertEqual(try Data(contentsOf:p.target),previous)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:p.stage.path).isEmpty)
  }
}
