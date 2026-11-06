import Foundation
import XCTest
@testable import MotionControllerIOS

final class ProtocolV1FixtureTests: XCTestCase {
    private var fixtureRoot: URL {
        get throws {
            let resourceURL = try XCTUnwrap(
                Bundle(for: Self.self).resourceURL,
                "The test bundle has no resource directory"
            )
            return resourceURL.appending(path: "golden-vectors", directoryHint: .isDirectory)
        }
    }

    func testEveryPositiveFixtureDecodesAndReencodesByteForByte() throws {
        let manifest = try loadManifest()
        let fixtures = try XCTUnwrap(manifest["positives"] as? [[String: Any]])
        XCTAssertEqual(fixtures.count, ProtocolV1.MessageType.allCases.count)

        var decodedTypes = Set<UInt8>()
        for fixture in fixtures {
            let relativePath = try XCTUnwrap(fixture["file"] as? String)
            let expectedType = try XCTUnwrap(fixture["message_type"] as? UInt8)
            let bytes = try Data(contentsOf: try fixtureRoot.appending(path: relativePath))
            let message = try ProtocolV1.decode(bytes)

            XCTAssertEqual(message.header.messageType.rawValue, expectedType, relativePath)
            XCTAssertEqual(try ProtocolV1.encode(message), bytes, relativePath)
            decodedTypes.insert(message.header.messageType.rawValue)
        }
        XCTAssertEqual(decodedTypes, Set(ProtocolV1.MessageType.allCases.map(\.rawValue)))
    }

    func testEveryNegativeFixtureReturnsItsManifestRejection() throws {
        let manifest = try loadManifest()
        let fixtures = try XCTUnwrap(manifest["negatives"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(fixtures.count, 5)

        for fixture in fixtures {
            let relativePath = try XCTUnwrap(fixture["file"] as? String)
            let expected = try XCTUnwrap(fixture["expected_rejection"] as? String)
            let bytes = try Data(contentsOf: try fixtureRoot.appending(path: relativePath))
            XCTAssertThrowsError(try ProtocolV1.decode(bytes), relativePath) { error in
                XCTAssertEqual((error as? ProtocolV1.CodecError)?.rawValue, expected, relativePath)
            }
        }
    }

    func testWorkedMotionValuesDecodeWithinManifestTolerance() throws {
        let manifest = try loadManifest()
        let tolerance = try XCTUnwrap(manifest["float_tolerance"] as? Double)
        let bytes = try Data(contentsOf: try fixtureRoot.appending(path: "positive/motion.bin"))
        let message = try ProtocolV1.decode(bytes)
        guard case let .motion(motion) = message.payload else {
            return XCTFail("Expected MOTION payload")
        }

        XCTAssertEqual(motion.sensorMonotonicNs, 123_456_789)
        XCTAssertEqual(Double(motion.acceleration.x), 1.0, accuracy: tolerance)
        XCTAssertEqual(Double(motion.acceleration.z), -9.80665, accuracy: tolerance)
        XCTAssertEqual(Double(motion.angularVelocity.y), -0.2, accuracy: tolerance)
        XCTAssertEqual(motion.orientation, SIMD4(0, 0, 0, 1))
        XCTAssertEqual(motion.accuracy, 3)
        XCTAssertEqual(motion.sensorFlags, 7)
    }

    private func loadManifest() throws -> [String: Any] {
        let data = try Data(contentsOf: try fixtureRoot.appending(path: "manifest.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
