package import Foundation
import FoundationModels

extension URLError {
    /// The error to throw for a failed connection: cancellation as `CancellationError`, a timeout as
    /// `LanguageModelError.timeout`, and any other failure as the `URLError` itself.
    package var thrownError: any Error {
        switch code {
        case .cancelled: CancellationError()
        case .timedOut: LanguageModelError.timeout(.init(debugDescription: localizedDescription))
        default: self
        }
    }
}
