#if os(tvOS)
import CoreModels
import CoreNetworking
import CoreUI
import SwiftUI
import TVUIKit
import UIKit

enum NativeEpisodeElement: Identifiable, Equatable {
    enum ID: Hashable {
        case episode(PlayerEpisodeEntry.ID), previousError, nextError
    }
    case episode(PlayerEpisodeEntry), previousError(AppError), nextError(AppError)

    var id: ID {
        switch self {
        case .episode(let entry): .episode(entry.id)
        case .previousError: .previousError
        case .nextError: .nextError
        }
    }
}

/// Native collection focus can realize the next cell without ending a held remote press.
struct PlayerEpisodeNativeRow: UIViewRepresentable {
    let items: [NativeEpisodeElement]
    let initialID: PlayerEpisodeEntry.ID?
    let layout: PlayerSequenceLayout
    @FocusState.Binding var focus: PlayerControls.FocusSlot?
    let onVisible: ([NativeEpisodeElement.ID]) -> Void
    let onFocus: (PlayerEpisodeEntry.ID) -> Void
    let onSelect: (NativeEpisodeElement) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = EpisodeCollectionLayout()
        layout.scrollDirection = .horizontal
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.clipsToBounds = false
        collection.showsHorizontalScrollIndicator = false
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(PlayerEpisodeNativeCell.self, forCellWithReuseIdentifier: "episode")
        context.coordinator.attach(collection)
        return collection
    }

    func updateUIView(_ collection: UICollectionView, context: Context) {
        context.coordinator.update(self, environment: context.environment)
    }

    static func dismantleUIView(_ collection: UICollectionView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, UICollectionViewDelegate {
        private weak var collection: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Int, NativeEpisodeElement.ID>?
        private var displayed: [NativeEpisodeElement] = []
        private var configuration: PlayerEpisodeNativeRow?
        private var environment = EnvironmentValues()
        private var initialPositionApplied = false
        private(set) var focusAnimations = 0
        private var publication: Task<Void, Never>?
        private var requestedFocus: IndexPath?
        private var lastInputFocus: PlayerControls.FocusSlot?
        private var focusedID: NativeEpisodeElement.ID?
        private var lastFocusedID: NativeEpisodeElement.ID?
        private var publishingNativeFocus = false

        func attach(_ collection: UICollectionView) {
            self.collection = collection
            collection.delegate = self
            dataSource = UICollectionViewDiffableDataSource<Int, NativeEpisodeElement.ID>(collectionView: collection) {
                [weak self] collection, path, id in
                guard let cell = collection.dequeueReusableCell(withReuseIdentifier: "episode", for: path)
                    as? PlayerEpisodeNativeCell else {
                    preconditionFailure("Episode registration must produce a native episode cell")
                }
                self?.configure(cell, id: id)
                return cell
            }
        }

        func stop() {
            publication?.cancel()
            publication = nil
            collection?.delegate = nil
            collection?.visibleCells.compactMap { $0 as? PlayerEpisodeNativeCell }.forEach { $0.cancelArtwork() }
        }

        func update(_ value: PlayerEpisodeNativeRow, environment: EnvironmentValues) {
            let presentationChanged = self.environment.locale != environment.locale
                || self.environment.displayScale != environment.displayScale
                || self.environment.colorScheme != environment.colorScheme
                || self.environment.layoutDirection != environment.layoutDirection
                || self.environment.dynamicTypeSize != environment.dynamicTypeSize
                || self.environment.isEnabled != environment.isEnabled
                || configuration?.layout.cardWidth != value.layout.cardWidth
                || configuration?.layout.imageHeight != value.layout.imageHeight
                || configuration?.layout.metrics.castNameFont != value.layout.metrics.castNameFont
                || configuration?.layout.metrics.castRoleFont != value.layout.metrics.castRoleFont
            self.environment = environment
            configuration = value
            guard let collection, let layout = collection.collectionViewLayout as? EpisodeCollectionLayout else { return }
            collection.semanticContentAttribute = environment.layoutDirection == .rightToLeft
                ? .forceRightToLeft : .forceLeftToRight
            let size = CGSize(width: value.layout.cardWidth, height: value.layout.rowHeight)
            if layout.itemSize != size || layout.minimumLineSpacing != value.layout.columnSpacing {
                layout.itemSize = size
                layout.minimumLineSpacing = value.layout.columnSpacing
                layout.minimumInteritemSpacing = 0
                layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: value.layout.metrics.contentPadding)
                layout.invalidateLayout()
            }
            apply(value)
            if presentationChanged {
                for case let cell as PlayerEpisodeNativeCell in collection.visibleCells {
                    if let path = collection.indexPath(for: cell), let id = dataSource?.itemIdentifier(for: path) {
                        configure(cell, id: id)
                    }
                }
            }
            if case .episodeItem(let id) = value.focus, focusedID == .episode(id) {
                publishingNativeFocus = false
            }
            if value.focus != lastInputFocus {
                lastInputFocus = value.focus
                if case .episodeItem(let id) = value.focus, focusedID != .episode(id), !publishingNativeFocus,
                   let index = displayed.firstIndex(where: { $0.id == .episode(id) }) {
                    requestedFocus = IndexPath(item: index, section: 0)
                }
            }
            schedulePublication()
        }

        private func configure(_ cell: PlayerEpisodeNativeCell, id: NativeEpisodeElement.ID) {
            guard let configuration, let item = displayed.first(where: { $0.id == id }) else { return }
            cell.configure(item, layout: configuration.layout, environment: environment)
        }

        private func apply(_ value: PlayerEpisodeNativeRow) {
            guard let collection, let dataSource else { return }
            let old = displayed
            guard old != value.items else { return }
            collection.layoutIfNeeded()
            let offset = collection.contentOffset.x
            // Use an episode anchor even when a leading retry row is inserted or removed.
            let anchor = old.first { if case .episode = $0 { return true }; return false }
            let oldIndex = anchor.flatMap { item in old.firstIndex(where: { $0.id == item.id }) } ?? 0
            let newIndex = anchor.flatMap { item in value.items.firstIndex(where: { $0.id == item.id }) } ?? 0
            displayed = value.items
            var snapshot = NSDiffableDataSourceSnapshot<Int, NativeEpisodeElement.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(displayed.map(\.id))
            let oldItems = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
            snapshot.reconfigureItems(displayed.compactMap { item in
                guard let previous = oldItems[item.id], previous != item else { return nil }
                return item.id
            })
            let pitch = value.layout.cardWidth + value.layout.columnSpacing
            let maximum = max(0, CGFloat(displayed.count) * pitch - value.layout.columnSpacing
                              + value.layout.metrics.contentPadding - collection.bounds.width)
            let logical = min(maximum, max(0, offset + CGFloat(newIndex - oldIndex) * pitch))
            let target = CGPoint(x: logical, y: 0)
            let layout = collection.collectionViewLayout as? EpisodeCollectionLayout
            if initialPositionApplied { layout?.preservedOffset = target }
            defer { layout?.preservedOffset = nil }
            UIView.performWithoutAnimation {
                dataSource.apply(snapshot, animatingDifferences: false)
                layout?.focusTarget = focusedID.flatMap { dataSource.indexPath(for: $0) }
                collection.layoutIfNeeded()
                if initialPositionApplied, abs(collection.contentOffset.x - target.x) > 0.5 {
                    let context = UICollectionViewFlowLayoutInvalidationContext()
                    context.contentOffsetAdjustment = CGPoint(x: target.x - collection.contentOffset.x, y: 0)
                    collection.collectionViewLayout.invalidateLayout(with: context)
                    collection.layoutIfNeeded()
                }
            }
        }

        private func setLogicalOffset(_ offset: CGFloat, in collection: UICollectionView) {
            let maximum = max(0, collection.contentSize.width - collection.bounds.width)
            let value = min(maximum, max(0, offset))
            collection.setContentOffset(CGPoint(x: value, y: 0), animated: false)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { schedulePublication() }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            if let cell = cell as? PlayerEpisodeNativeCell,
               let id = dataSource?.itemIdentifier(for: indexPath) {
                configure(cell, id: id)
            }
            schedulePublication()
        }

        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            (cell as? PlayerEpisodeNativeCell)?.cancelArtwork()
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard environment.isEnabled, displayed.indices.contains(indexPath.item) else { return }
            configuration?.onSelect(displayed[indexPath.item])
        }

        func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
            environment.isEnabled
        }

        func collectionView(
            _ collectionView: UICollectionView, shouldUpdateFocusIn context: UICollectionViewFocusUpdateContext
        ) -> Bool {
            (collectionView.collectionViewLayout as? EpisodeCollectionLayout)?.focusTarget = context.nextFocusedIndexPath
            return context.nextFocusedIndexPath == nil || environment.isEnabled
        }

        func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
            requestedFocus ?? lastFocusedID.flatMap { dataSource?.indexPath(for: $0) }
        }

        func requestFocus(at indexPath: IndexPath) {
            guard let collection, let system = UIFocusSystem.focusSystem(for: collection) else { return }
            requestedFocus = indexPath
            system.requestFocusUpdate(to: collection)
            system.updateFocusIfNeeded()
            requestedFocus = nil
        }

        func collectionView(
            _ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
            with coordinator: UIFocusAnimationCoordinator
        ) {
            focusedID = context.nextFocusedIndexPath.flatMap { dataSource?.itemIdentifier(for: $0) }
            if let focusedID { lastFocusedID = focusedID }
            // SwiftUI can echo the collection's previous binding before observing
            // the native cell. That echo is not a new request to move focus back.
            publishingNativeFocus = focusedID != nil
            focusAnimations += 1
            schedulePublication()
            coordinator.addCoordinatedAnimations({}) { [weak self] in
                guard let self else { return }
                focusAnimations -= 1
            }
        }

        private func schedulePublication() {
            guard publication == nil else { return }
            publication = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, let collection, let configuration else { return }
                publication = nil
                guard collection.window != nil, collection.bounds.width > 0 else { return }
                if !initialPositionApplied, !displayed.isEmpty {
                    let index = configuration.initialID.flatMap { id in
                        displayed.firstIndex(where: { $0.id == .episode(id) })
                    } ?? 0
                    initialPositionApplied = true
                    collection.layoutIfNeeded()
                    setLogicalOffset(CGFloat(index) * (configuration.layout.cardWidth + configuration.layout.columnSpacing),
                                     in: collection)
                    collection.layoutIfNeeded()
                }
                if let requestedFocus {
                    collection.scrollToItem(at: requestedFocus, at: [], animated: false)
                    collection.layoutIfNeeded()
                    requestFocus(at: requestedFocus)
                }
                let actualCell = UIFocusSystem.focusSystem(for: collection)?.focusedItem as? UICollectionViewCell
                focusedID = actualCell.flatMap { collection.indexPath(for: $0) }
                    .flatMap { dataSource?.itemIdentifier(for: $0) }
                if case .episode(let id) = focusedID { configuration.onFocus(id) }
                let visible = collection.collectionViewLayout.layoutAttributesForElements(in: collection.bounds)?
                    .filter { $0.representedElementCategory == .cell && $0.frame.intersects(collection.bounds) }
                    .map(\.indexPath.item) ?? []
                guard let first = visible.min(), let last = visible.max(), !displayed.isEmpty else { return }
                let range = max(0, first - 1)..<min(displayed.count, last + 2)
                configuration.onVisible(displayed[range].map(\.id))
            }
        }
    }
}

final class PlayerEpisodeNativeCell: UICollectionViewCell {
    private var element: NativeEpisodeElement?
    private var layout: PlayerSequenceLayout?
    private var artwork: UIImage?
    private var preparedArtwork: UIImage?
    private var references: [ArtworkReference] = []
    private var imageTask: Task<Void, Never>?
    private var revision = UUID()
    private var caption: (UIView & UIContentView)?
    private var enabled = true
    private var environment = EnvironmentValues()

    override var canBecomeFocused: Bool { element != nil && enabled }

    func configure(_ element: NativeEpisodeElement, layout: PlayerSequenceLayout, environment: EnvironmentValues) {
        let needsArtworkUpdate = self.element != element || self.layout?.imageWidth != layout.imageWidth
            || self.layout?.imageHeight != layout.imageHeight
            || self.layout?.metrics.castNameFont != layout.metrics.castNameFont
            || self.layout?.metrics.castRoleFont != layout.metrics.castRoleFont
            || self.environment.displayScale != environment.displayScale
            || self.environment.locale != environment.locale
            || self.environment.colorScheme != environment.colorScheme
            || self.environment.layoutDirection != environment.layoutDirection
            || self.environment.dynamicTypeSize != environment.dynamicTypeSize
        self.element = element
        self.layout = layout
        self.environment = environment
        enabled = environment.isEnabled
        clipsToBounds = false
        contentView.clipsToBounds = false
        backgroundConfiguration = .clear()
        isAccessibilityElement = true
        accessibilityTraits = .button
        switch element {
        case .episode(let entry):
            accessibilityLabel = entry.item.title
            accessibilityValue = entry.badge
            let captionConfiguration = UIHostingConfiguration {
                Text(verbatim: entry.item.title)
                    .font(layout.metrics.castNameFont)
                    .lineLimit(layout.compact ? 1 : 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .environment(\.self, environment)
            }.margins(.all, 0)
            if let caption {
                caption.configuration = captionConfiguration
            } else {
                let caption = captionConfiguration.makeContentView()
                caption.isUserInteractionEnabled = false
                caption.accessibilityElementsHidden = true
                self.caption = caption
                addSubview(caption)
            }
            let references = entry.item.artworkReferences(for: .episodeThumbnail)
            if references != self.references {
                imageTask?.cancel()
                self.references = references
                artwork = nil
                revision = UUID()
                let revision = revision
                imageTask = Task { [weak self] in
                    let result = await ArtworkFirstPaintResolver.resolve(
                        references: references, variant: .landscapeCard, maxAspectRatio: nil,
                        asyncOnlineURL: nil, maximumOnlineWait: 0, prefersOnlineArtwork: false
                    )
                    guard !Task.isCancelled, let self, self.revision == revision else { return }
                    artwork = result?.image
                    prepareArtwork()
                    setNeedsUpdateConfiguration()
                }
            }
        case .previousError(let error), .nextError(let error):
            var title: LocalizedStringResource = element.id == .previousError ? "Earlier episodes" : "Later episodes"
            var message = error.userMessage
            var retry: LocalizedStringResource = "Try Again"
            title.locale = environment.locale
            message.locale = environment.locale
            retry.locale = environment.locale
            accessibilityLabel = String(localized: title) + ". " + String(localized: message) // l10n:content — localized UIKit accessibility text
            accessibilityValue = String(localized: retry) // l10n:content — localized UIKit accessibility text
            caption?.removeFromSuperview()
            caption = nil
        }
        if needsArtworkUpdate { prepareArtwork() }
        setNeedsUpdateConfiguration()
        setNeedsLayout()
    }

    private func prepareArtwork() {
        guard let element, let layout else { return }
        // Keep static chrome in the same bitmap as TVUIKit's native focus projection.
        // Render only for a new item, bitmap or presentation, never for a focus change.
        let renderer = ImageRenderer(content: NativeEpisodeCellArtwork(
            element: element, image: artwork, layout: layout
        ).environment(\.self, environment)
            .frame(width: layout.imageWidth, height: layout.imageHeight)
            .clipped())
        renderer.scale = environment.displayScale
        renderer.isOpaque = true
        preparedArtwork = renderer.uiImage
        if preparedArtwork == nil {
            PlozzLog.app.error("Unable to render episode artwork chrome")
        }
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        var configuration = TVMediaItemContentConfiguration.wideCell()
        configuration.image = preparedArtwork ?? artwork ?? Self.placeholder
        contentConfiguration = configuration.updated(for: state)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout else { return }
        let inset = layout.cardMetrics.cardInset
        contentView.frame = CGRect(x: inset, y: inset, width: layout.imageWidth, height: layout.imageHeight)
        contentView.layoutIfNeeded()
        caption?.frame = CGRect(
            x: inset + layout.cardMetrics.landscapeCaptionInset,
            y: contentView.frame.maxY + layout.cardMetrics.landscapeCaptionTopSpacing,
            width: layout.imageWidth - layout.cardMetrics.landscapeCaptionInset * 2,
            height: layout.titleHeight
        )
    }

    func cancelArtwork() {
        imageTask?.cancel()
        imageTask = nil
        if artwork == nil { references = [] }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelArtwork()
        revision = UUID()
        references = []
        artwork = nil
        preparedArtwork = nil
        element = nil
        accessibilityLabel = nil
        accessibilityValue = nil
        caption?.removeFromSuperview()
        caption = nil
    }

    private struct NativeEpisodeCellArtwork: View {
        let element: NativeEpisodeElement
        let image: UIImage?
        let layout: PlayerSequenceLayout

        var body: some View {
            Color(uiColor: .darkGray)
                .overlay {
                    switch element {
                    case .episode(let entry):
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                        if let badge = entry.badge {
                            PlayerEpisodeArtworkOverlay(badge: badge, layout: layout)
                        }
                    case .previousError(let error), .nextError(let error):
                        VStack(alignment: .leading, spacing: 8) {
                            Text(element.id == .previousError
                                 ? LocalizedStringResource("Earlier episodes") : LocalizedStringResource("Later episodes"))
                                .font(layout.metrics.castNameFont)
                            Text(error.userMessage).font(.caption).lineLimit(2)
                            Text("Try Again").font(.caption.bold())
                        }
                        .padding(layout.metrics.contentPadding)
                    }
                }
        }
    }

    private static let placeholder = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image {
        UIColor.darkGray.setFill()
        $0.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
    }
}

private final class EpisodeCollectionLayout: UICollectionViewFlowLayout {
    var preservedOffset: CGPoint?
    var focusTarget: IndexPath?
    override var flipsHorizontallyInOppositeLayoutDirection: Bool { true }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        aligned(proposedContentOffset)
    }

    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        aligned(proposedContentOffset)
    }

    private func aligned(_ proposed: CGPoint) -> CGPoint {
        if let preservedOffset { return preservedOffset }
        guard let collectionView, let focusTarget,
              let frame = layoutAttributesForItem(at: focusTarget)?.frame,
              frame.width <= collectionView.bounds.width else { return proposed }
        let pitch = itemSize.width + minimumLineSpacing
        guard pitch > 0 else { return proposed }
        let maximum = max(0, collectionViewContentSize.width - collectionView.bounds.width)
        // A nearest-slot snap alone can leave the focused card clipped at the trailing edge.
        let lower = min(maximum, max(0, ceil((frame.maxX - collectionView.bounds.width) / pitch) * pitch))
        let upper = min(maximum, max(0, floor(frame.minX / pitch) * pitch))
        let slot = (proposed.x / pitch).rounded() * pitch
        return CGPoint(x: min(upper, max(lower, slot)), y: proposed.y)
    }
}
#endif
