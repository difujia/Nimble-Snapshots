import Foundation
import FBSnapshotTestCase
import UIKit
import Nimble
import QuartzCore
import Quick

@objc public protocol Snapshotable {
    var snapshotObject: UIView? { get }
}

extension UIViewController : Snapshotable {
    public var snapshotObject: UIView? {
        self.beginAppearanceTransition(true, animated: false)
        self.endAppearanceTransition()
        return view
    }
}

extension UIView : Snapshotable {
    public var snapshotObject: UIView? {
        return self
    }
}

@objc class FBSnapshotTest : NSObject {

    var currentExampleMetadata: ExampleMetadata?

    var referenceImagesDirectory: String?
    var tolerance: CGFloat = 0
    
    class var sharedInstance : FBSnapshotTest {
        struct Instance {
            static let instance: FBSnapshotTest = FBSnapshotTest()
        }
        return Instance.instance
    }

    class func setReferenceImagesDirectory(directory: String?) {
        sharedInstance.referenceImagesDirectory = directory
    }

    class func compareSnapshot(instance: Snapshotable, isDeviceAgnostic: Bool = false, usesDrawRect: Bool = false, snapshot: String, record: Bool, referenceDirectory: String, tolerance: CGFloat) -> Bool {
        let snapshotController: FBSnapshotTestController = FBSnapshotTestController(testName: testFileName())
        snapshotController.isDeviceAgnostic = isDeviceAgnostic
        snapshotController.recordMode = record
        snapshotController.referenceImagesDirectory = referenceDirectory
        snapshotController.usesDrawViewHierarchyInRect = usesDrawRect
        
        assert(snapshotController.referenceImagesDirectory != nil, "Missing value for referenceImagesDirectory - Call FBSnapshotTest.setReferenceImagesDirectory(FB_REFERENCE_IMAGE_DIR)")

        do {
            try snapshotController.compareSnapshot(ofViewOrLayer: instance.snapshotObject, selector: Selector(snapshot), identifier: nil, tolerance: tolerance)
        }
        catch {
            return false;
        }
        return true;
    }
}

// Note that these must be lower case.
var testFolderSuffixes = ["tests", "specs"]

public func setNimbleTestFolder(testFolder: String) {
    testFolderSuffixes = [testFolder.lowercased()]
}

public func setNimbleTolerance(tolerance: CGFloat) {
    FBSnapshotTest.sharedInstance.tolerance = tolerance
}

func _getDefaultReferenceDirectory(sourceFileName: String) -> String {
    if let globalReference = FBSnapshotTest.sharedInstance.referenceImagesDirectory {
        return globalReference
    }

    // Search the test file's path to find the first folder with a test suffix,
    // then append "/ReferenceImages" and use that.

    // Grab the file's path
    let pathComponents = (sourceFileName as NSString).pathComponents

    // Find the directory in the path that ends with a test suffix.
    let testPath = pathComponents.filter { component -> Bool in
        return testFolderSuffixes.filter { component.lowercased().hasSuffix($0) }.count > 0
        }.first

    guard let testDirectory = testPath, let currentIndex = pathComponents.index(of: testDirectory) else {
        fatalError("Could not infer reference image folder – You should provide a reference dir using FBSnapshotTest.setReferenceImagesDirectory(FB_REFERENCE_IMAGE_DIR)")
    }

    // Recombine the path components and append our own image directory.
    let folderPathComponents = pathComponents[0...currentIndex]
    let folderPath = folderPathComponents.joined(separator: "/")

    return folderPath + "/ReferenceImages"
}

private func testFileName() -> String {
    let name = FBSnapshotTest.sharedInstance.currentExampleMetadata!.example.callsite.file as NSString
    let type = ".\(name.pathExtension)"
    let sanitizedName = name.lastPathComponent.replacingOccurrences(of: type, with: "")

    return sanitizedName
}

private func sanitizedTestName(name: String?) -> String {
    let quickExample = FBSnapshotTest.sharedInstance.currentExampleMetadata
    var filename = name ?? quickExample!.example.name
    filename = filename.replacingOccurrences(of: "root example group, ", with: "")
    let characterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
    let components = filename.components(separatedBy: characterSet.inverted)
    return components.joined(separator: "_")
}

func _getTolerance() -> CGFloat {
    return FBSnapshotTest.sharedInstance.tolerance
}

func _clearFailureMessage(failureMessage: FailureMessage) {
    failureMessage.actualValue = ""
    failureMessage.expected = ""
    failureMessage.postfixMessage = ""
    failureMessage.to = ""
}

private func performSnapshotTest(name: String?, isDeviceAgnostic: Bool = false, usesDrawRect: Bool = false, actualExpression: Expression<Snapshotable>, failureMessage: FailureMessage, tolerance: CGFloat?) -> Bool {
    let instance = try! actualExpression.evaluate()!
    let testFileLocation = actualExpression.location.file
    let referenceImageDirectory = _getDefaultReferenceDirectory(sourceFileName: testFileLocation)
    let snapshotName = sanitizedTestName(name: name)
    let tolerance = tolerance ?? _getTolerance()

    let result = FBSnapshotTest.compareSnapshot(instance: instance, isDeviceAgnostic: isDeviceAgnostic, usesDrawRect: usesDrawRect, snapshot: snapshotName, record: false, referenceDirectory: referenceImageDirectory, tolerance: tolerance)

    if !result {
        _clearFailureMessage(failureMessage: failureMessage)
        failureMessage.actualValue = "expected a matching snapshot in \(snapshotName)"
    }

    return result
}

func _recordSnapshot(name: String?, isDeviceAgnostic: Bool=false, usesDrawRect: Bool=false, actualExpression: Expression<Snapshotable>, failureMessage: FailureMessage) -> Bool {
    let instance = try! actualExpression.evaluate()!
    let testFileLocation = actualExpression.location.file
    let referenceImageDirectory = _getDefaultReferenceDirectory(sourceFileName: testFileLocation)
    let snapshotName = sanitizedTestName(name: name)
    let tolerance = _getTolerance()
    
    _clearFailureMessage(failureMessage: failureMessage)

    if FBSnapshotTest.compareSnapshot(instance: instance, isDeviceAgnostic: isDeviceAgnostic, usesDrawRect: usesDrawRect, snapshot: snapshotName, record: true, referenceDirectory: referenceImageDirectory, tolerance: tolerance) {
        failureMessage.actualValue = "snapshot \(name ?? snapshotName) successfully recorded, replace recordSnapshot with a check"
    } else {
        failureMessage.actualValue = "expected to record a snapshot in \(name)"
    }

    return false
}

internal var switchChecksWithRecords = false

public func haveValidSnapshot(named name: String? = nil, usesDrawRect: Bool = false, tolerance: CGFloat? = nil) -> MatcherFunc<Snapshotable> {
    return MatcherFunc { actualExpression, failureMessage in
        if (switchChecksWithRecords) {
            return _recordSnapshot(name: name, usesDrawRect: usesDrawRect, actualExpression: actualExpression, failureMessage: failureMessage)
        }

        return performSnapshotTest(name: name, usesDrawRect: usesDrawRect, actualExpression: actualExpression, failureMessage: failureMessage, tolerance: tolerance)
    }
}

public func haveValidDeviceAgnosticSnapshot(named name: String?=nil, usesDrawRect: Bool=false, tolerance: CGFloat? = nil) -> MatcherFunc<Snapshotable> {
    return MatcherFunc { actualExpression, failureMessage in
        if (switchChecksWithRecords) {
            return _recordSnapshot(name: name, isDeviceAgnostic: true, usesDrawRect: usesDrawRect, actualExpression: actualExpression, failureMessage: failureMessage)
        }

        return performSnapshotTest(name: name, isDeviceAgnostic: true, usesDrawRect: usesDrawRect, actualExpression: actualExpression, failureMessage: failureMessage, tolerance: tolerance)
    }
}

public func recordSnapshot(named name: String? = nil, usesDrawRect: Bool=false) -> MatcherFunc<Snapshotable> {
    return MatcherFunc { actualExpression, failureMessage in
        return _recordSnapshot(name: name, usesDrawRect: usesDrawRect, actualExpression: actualExpression, failureMessage: failureMessage)
    }
}

public func recordDeviceAgnosticSnapshot(named name: String?=nil, usesDrawRect: Bool=false) -> MatcherFunc<Snapshotable> {
    return MatcherFunc { actualExpression, failureMessage in
        return _recordSnapshot(name: name, isDeviceAgnostic: true, usesDrawRect: usesDrawRect, actualExpression: actualExpression, failureMessage: failureMessage)
    }
}
