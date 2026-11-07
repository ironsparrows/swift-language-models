extension ModelReasoning {
    /// The reasoning two models share, such as a model and its fallback: none when either doesn't reason, always when
    /// either always reasons, and by default only when both reason by default.
    package func sharing(_ other: Self) -> Self {
        if !isSupported || !other.isSupported { return .unsupported }
        if !canBeTurnedOff || !other.canBeTurnedOff { return .mandatory }
        return isEnabledByDefault && other.isEnabledByDefault ? .onByDefault : .offByDefault
    }
}

extension Optional where Wrapped: Comparable {
    /// The smaller of two limits that two models share, such as their context sizes, or the one that's known.
    package func smallerLimit(_ other: Self) -> Self {
        switch (self, other) {
        case (let limit?, let other?): Swift.min(limit, other)
        case (let limit?, nil): limit
        case (nil, let other): other
        }
    }
}
