@preconcurrency import CoreML
import XCTest

@testable import FluidAudio

final class TtsComputeUnitPresetTests: XCTestCase {

    // MARK: - init?(cliValue:)

    func testCliValueParsing_canonicalKebabCase() {
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "default"), .default)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "all-ane"), .allAne)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "cpu-and-gpu"), .cpuAndGpu)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "cpu-only"), .cpuOnly)
    }

    func testCliValueParsing_aliases() {
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "ane"), .allAne)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "neural-engine"), .allAne)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "cpuandgpu"), .cpuAndGpu)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "gpu"), .cpuAndGpu)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "cpu"), .cpuOnly)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "cpuonly"), .cpuOnly)
    }

    func testCliValueParsing_caseInsensitive() {
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "DEFAULT"), .default)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "All-Ane"), .allAne)
        XCTAssertEqual(TtsComputeUnitPreset(cliValue: "CPU-AND-GPU"), .cpuAndGpu)
    }

    func testCliValueParsing_unknownReturnsNil() {
        XCTAssertNil(TtsComputeUnitPreset(cliValue: ""))
        XCTAssertNil(TtsComputeUnitPreset(cliValue: "fastest"))
        XCTAssertNil(TtsComputeUnitPreset(cliValue: "all_ane"))  // underscore rejected
        XCTAssertNil(TtsComputeUnitPreset(cliValue: "ane-only"))
        XCTAssertNil(TtsComputeUnitPreset(cliValue: "neuralengine"))
    }

    // MARK: - cliValue (round-trip)

    func testCliValueRoundTrip() {
        for preset in TtsComputeUnitPreset.allCases {
            let canonical = preset.cliValue
            XCTAssertEqual(
                TtsComputeUnitPreset(cliValue: canonical), preset,
                "cliValue '\(canonical)' must round-trip back to \(preset)")
        }
    }

    func testCliValueIsKebabCase() {
        XCTAssertEqual(TtsComputeUnitPreset.default.cliValue, "default")
        XCTAssertEqual(TtsComputeUnitPreset.allAne.cliValue, "all-ane")
        XCTAssertEqual(TtsComputeUnitPreset.cpuAndGpu.cliValue, "cpu-and-gpu")
        XCTAssertEqual(TtsComputeUnitPreset.cpuOnly.cliValue, "cpu-only")
    }

    // MARK: - uniformUnits

    func testUniformUnits_defaultIsNil() {
        XCTAssertNil(TtsComputeUnitPreset.default.uniformUnits)
    }

    func testUniformUnits_concretePresets() {
        XCTAssertEqual(TtsComputeUnitPreset.allAne.uniformUnits, .cpuAndNeuralEngine)
        XCTAssertEqual(TtsComputeUnitPreset.cpuAndGpu.uniformUnits, .cpuAndGPU)
        XCTAssertEqual(TtsComputeUnitPreset.cpuOnly.uniformUnits, .cpuOnly)
    }

}
