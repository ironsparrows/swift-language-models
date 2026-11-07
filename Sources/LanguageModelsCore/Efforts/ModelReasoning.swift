/// Whether and when a model reasons, and whether a request can turn its reasoning off.
public struct ModelReasoning: Sendable, Hashable {
    /// The model doesn't reason.
    public static let unsupported = Self(.unsupported)

    /// The model reasons only when a request asks it to.
    public static let offByDefault = Self(.offByDefault)

    /// The model reasons unless a request turns reasoning off.
    public static let onByDefault = Self(.onByDefault)

    /// The model always reasons, so a request can't turn reasoning off.
    public static let mandatory = Self(.mandatory)

    private enum Mode: Hashable {
        case unsupported, offByDefault, onByDefault, mandatory
    }

    private let mode: Mode

    private init(_ mode: Mode) {
        self.mode = mode
    }

    /// Whether the model reasons at all.
    public var isSupported: Bool {
        mode != .unsupported
    }

    /// Whether the model reasons when a request doesn't set a reasoning level.
    public var isEnabledByDefault: Bool {
        mode == .onByDefault || mode == .mandatory
    }

    /// Whether a request can turn the model's reasoning off.
    public var canBeTurnedOff: Bool {
        mode == .offByDefault || mode == .onByDefault
    }
}
