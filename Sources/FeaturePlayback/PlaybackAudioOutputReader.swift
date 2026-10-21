#if canImport(AVFoundation)
import AVFoundation
import CoreModels
import Foundation

@MainActor
enum PlaybackAudioOutputReader {
    static func read() -> PlaybackDiagnostics.AudioOutput? {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        return facts(renderingMode: session.renderingMode, ports: session.currentRoute.outputs.map(\.portType))
        #else
        return nil
        #endif
    }

    #if os(iOS) || os(tvOS)
    static func facts(
        renderingMode: AVAudioSession.RenderingMode, ports: [AVAudioSession.Port]
    ) -> PlaybackDiagnostics.AudioOutput? {
        guard !ports.isEmpty else { return nil }
        var connections: [PlaybackDiagnostics.AudioOutput.Label] = []
        for port in ports {
            if let label = connection(port), !connections.contains(label) {
                connections.append(label)
            }
        }
        let mode: PlaybackDiagnostics.AudioOutput.Label?
        switch renderingMode {
        case .notApplicable: mode = nil
        case .monoStereo: mode = .localized("Mono / Stereo")
        case .surround: mode = .localized("Surround")
        case .spatialAudio: mode = .localized("Spatial Audio")
        case .dolbyAudio: mode = .format("Dolby Audio")
        case .dolbyAtmos: mode = .format("Dolby Atmos")
        @unknown default: mode = nil
        }
        guard mode != nil || !connections.isEmpty else { return nil }
        return .init(renderingMode: mode, connections: connections)
    }

    private static func connection(_ port: AVAudioSession.Port) -> PlaybackDiagnostics.AudioOutput.Label? {
        // Port names and UIDs can contain personal device names. Only fixed types
        // cross this boundary; channel counts cannot establish Atmos or speakers.
        switch port {
        case .HDMI: .format("HDMI")
        case .airPlay: .format("AirPlay")
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: .format("Bluetooth")
        case .headphones: .localized("Headphones")
        case .builtInSpeaker: .localized("Built-in speakers")
        case .builtInReceiver: .localized("Built-in receiver")
        case .usbAudio: .format("USB")
        case .lineOut: .localized("Line out")
        case .carAudio: .localized("Car audio")
        case .displayPort: .format("DisplayPort")
        case .thunderbolt: .format("Thunderbolt")
        case .fireWire: .format("FireWire")
        case .AVB: .format("AVB")
        case .PCI: .format("PCI")
        case .virtual: .localized("Virtual audio")
        default: nil
        }
    }
    #endif
}
#endif
