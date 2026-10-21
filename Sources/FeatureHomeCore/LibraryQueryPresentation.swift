import CoreModels
import Foundation
import Observation

@MainActor
@Observable
final class LibraryQueryPresentation {
    var filters: LibraryFilters = .all
    var facets = LibraryQueryFacets()
    var facetsLoading = false
    var facetsError: AppError?
    @ObservationIgnored var hasLoadedFacets = false
    @ObservationIgnored var facetsRevision = 0
    @ObservationIgnored var facetsTask: Task<Void, Never>?
    var progress: Double?
    var message: LocalizedStringResource?
    var failureDiagnostic: LibraryLoadDiagnostic?
    var collectionProgress: LibraryCollectionProgress?
    var collectionScanIncomplete = false
    var firstPageLoading = false
    var capabilitiesRevision = 0
}
