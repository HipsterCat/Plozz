#if os(iOS)
import CoreModels
import CoreUI
import FeatureHomeCore
import SwiftUI

struct PlozziOSPlayerVersionSheet: View {
    let item: MediaItem
    let mediaSourceID: String?
    var onlySDR = false
    let onSelect: (String) -> Void

    var body: some View {
        let versions = onlySDR
            ? PlayerVersionSelection.sdrAlternatives(for: item, mediaSourceID: mediaSourceID)
            : PlayerVersionSelection.versions(for: item)
        let selectedID = versions.first {
            PlayerVersionSelection.isSelected($0, item: item, mediaSourceID: mediaSourceID)
        }?.id
        MediaVersionPicker(
            versions: versions,
            selectedVersionID: selectedID,
            title: onlySDR ? "SDR versions" : "Version",
            footer: "Resumes at the current position. Different cuts may have different timing."
        ) { id in
            if id != selectedID {
                onSelect(id)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
