import OpenRouterLanguageModels
import Testing

/// Which failures of a live request cancel its test, as a host's that no request could avoid, and which fail it.
@Suite("Unavailable hosts")
struct HostUnavailabilityTests {
    @Test(arguments: [
        ("No endpoints found for vendor/model.", HostUnavailability?.some(.brief)),
        ("No endpoints found that support the requested output modalities: image, text", nil),
        ("No endpoints found: Paid model training violation (account settings)", .excludedByAccountSettings),
    ])
    func `a 404 with no endpoints counts as an unavailable host, unless no endpoint returns the output kinds asked for`(
        message: String,
        unavailability: HostUnavailability?
    ) {
        #expect(HostUnavailability(OpenRouterError(status: 404, message: message)) == unavailability)
    }
}
