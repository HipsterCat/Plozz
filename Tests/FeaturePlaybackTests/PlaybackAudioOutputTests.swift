#if os(iOS) || os(tvOS)
import AVFoundation
import CoreModels
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlaybackAudioOutputTests: XCTestCase {
    func testRenderingModesComeOnlyFromTheSystemAndNotFromChannelCounts() {
        let cases: [(AVAudioSession.RenderingMode, PlaybackDiagnostics.AudioOutput.Label?)] = [
            (.notApplicable, nil), (.monoStereo, .localized("Mono / Stereo")), (.surround, .localized("Surround")),
            (.spatialAudio, .localized("Spatial Audio")), (.dolbyAudio, .format("Dolby Audio")), (.dolbyAtmos, .format("Dolby Atmos"))
        ]
        for (mode, expected) in cases {
            let facts = PlaybackAudioOutputReader.facts(renderingMode: mode, ports: [.HDMI])
            XCTAssertEqual(facts?.renderingMode, expected)
            XCTAssertEqual(facts?.connections, [.format("HDMI")])
        }
        XCTAssertNil(PlaybackAudioOutputReader.facts(renderingMode: .dolbyAtmos, ports: []))
        XCTAssertNil(PlaybackAudioOutputReader.facts(
            renderingMode: .notApplicable, ports: [.init(rawValue: "unrecognized-private-device")]
        ))
    }

    func testConnectionsAreFixedLabelsWithNoDeviceNamesOrDuplicateBluetoothRows() {
        let facts = PlaybackAudioOutputReader.facts(renderingMode: .spatialAudio, ports: [
            .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .usbAudio, .headphones,
            .builtInSpeaker, .builtInReceiver, .lineOut, .carAudio, .displayPort, .thunderbolt,
            .fireWire, .AVB, .PCI, .virtual, .init(rawValue: "private-device-name")
        ])
        XCTAssertEqual(facts?.connections, [
            .format("Bluetooth"), .format("AirPlay"), .format("USB"), .localized("Headphones"),
            .localized("Built-in speakers"), .localized("Built-in receiver"), .localized("Line out"),
            .localized("Car audio"), .format("DisplayPort"), .format("Thunderbolt"), .format("FireWire"),
            .format("AVB"), .format("PCI"), .localized("Virtual audio")
        ])
    }

    func testSystemOutputRefreshesAndClearsForEveryPlaybackMode() {
        for mode: PlaybackDiagnostics.PlaybackMode in [.plozzigen, .directPlay, .remux, .transcode] {
            var output: PlaybackDiagnostics.AudioOutput? = .init(renderingMode: .format("Dolby Atmos"), connections: [.format("HDMI")])
            let sampler = PlaybackDiagnosticsSampler(audioOutputReader: { output })
            defer { sampler.stop() }
            sampler.start(player: nil, mode: mode, metadata: .init(
                audio: .init(codec: "truehd", profile: "Dolby Atmos", channels: 8)
            ))
            sampler.sampleTick()
            XCTAssertEqual(sampler.latest?.audioOutput, output)
            output = .init(renderingMode: .localized("Mono / Stereo"), connections: [.format("Bluetooth")])
            sampler.sampleTick()
            XCTAssertEqual(sampler.latest?.audioOutput, output, "A route change must replace the old Atmos output")
            output = .init(connections: [.format("AirPlay")])
            sampler.sampleTick()
            XCTAssertNil(sampler.latest?.audioOutput?.renderingMode)
            XCTAssertEqual(sampler.latest?.audioOutput?.connections, [.format("AirPlay")])
            output = nil
            sampler.sampleTick()
            XCTAssertNil(sampler.latest?.audioOutput, "No measurement must not fall back to source Atmos")
        }
    }

    func testHiddenDiagnosticsAndStoppedSessionsDoNotReadOrRetainSystemOutput() {
        var reads = 0
        let sampler = PlaybackDiagnosticsSampler(audioOutputReader: {
            reads += 1
            return .init(renderingMode: .format("Dolby Atmos"), connections: [.format("HDMI")])
        })
        sampler.start(player: nil, mode: .plozzigen, includesSystemMetrics: false)
        sampler.sampleTick()
        XCTAssertEqual(reads, 0)
        sampler.setSystemMetricsEnabled(true)
        sampler.sampleTick()
        XCTAssertEqual(reads, 1)
        XCTAssertNotNil(sampler.latest?.audioOutput)
        sampler.setSystemMetricsEnabled(false)
        sampler.sampleTick()
        XCTAssertEqual(reads, 1)
        XCTAssertNil(sampler.latest?.audioOutput)
        sampler.setSystemMetricsEnabled(true)
        sampler.sampleTick()
        sampler.stop()
        XCTAssertNil(sampler.latest?.audioOutput)
        sampler.sampleTick()
        XCTAssertEqual(reads, 2)
    }
}
#endif
