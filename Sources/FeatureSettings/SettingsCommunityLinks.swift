#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI

public struct SettingsCommunityLinks: View {
    private let repoURL: String
    private let compact: Bool

    public init(repoURL: String = AppLinks.repository.absoluteString, compact: Bool = false) {
        self.repoURL = repoURL
        self.compact = compact
    }

    public var body: some View {
        #if os(tvOS)
        if compact {
            HStack(spacing: SettingsFormMetrics.illustratedGroupSpacing) {
                codes
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            adaptiveCards
        }
        #else
        adaptiveCards
        #endif
    }

    private var adaptiveCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: compact ? 12 : 24) {
                codes
            }
            VStack(spacing: compact ? 12 : 24) {
                codes
            }
        }
    }

    @ViewBuilder
    private var codes: some View {
        SettingsCommunityCard.discord(compact: compact)
        SettingsCommunityCard(
            brand: .github,
            caption: "Source code and issues",
            url: repoURL,
            accessibilityLabel: "Scan to view the Plozz GitHub repository",
            compact: compact
        )
    }
}

struct SettingsCommunityCard: View {
    let brand: SettingsCommunityLogo.Brand
    let caption: LocalizedStringKey
    let url: String
    let accessibilityLabel: LocalizedStringKey
    var compact = false

    static func discord(caption: LocalizedStringKey = "Join the community", compact: Bool = false) -> Self {
        Self(
            brand: .discord,
            caption: caption,
            url: AppLinks.discord.absoluteString,
            accessibilityLabel: "Scan to join the Plozz Discord community",
            compact: compact
        )
    }

    var body: some View {
        SettingsPanel(contentPadding: compact
                      ? EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
                      : .settingsPanelDefault) {
            #if os(tvOS)
            if compact {
                HStack(spacing: SettingsFormMetrics.illustratedGroupSpacing) {
                    identity(brand: brand, caption: caption)
                    qrCode(url)
                }
                .frame(maxHeight: .infinity)
            } else {
                adaptiveContent
            }
            #else
            adaptiveContent
            #endif
        }
        .frame(idealWidth: compact ? 400 : 560, maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var adaptiveContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: compact ? 16 : 24) {
                identity(brand: brand, caption: caption)
                qrCode(url)
            }
            VStack(alignment: .leading, spacing: 24) {
                identity(brand: brand, caption: caption)
                qrCode(url)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func identity(
        brand: SettingsCommunityLogo.Brand,
        caption: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            SettingsCommunityLogo(brand: brand, height: compact ? 28 : 40)
            Text(caption)
                .font(compact ? SettingsRowMetrics.helperFont : .caption)
                .plozzForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
    }

    private func qrCode(_ url: String) -> some View {
        SettingsQRCode(string: url, centerMark: nil)
            .frame(width: compact ? 144 : 180, height: compact ? 144 : 180)
            .accessibilityHidden(true)
    }
}
#endif
