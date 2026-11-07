/// No members: what a provider adds to a request, or reads from a response, when it adds or reads nothing beyond the
/// format's own.
///
/// It encodes as an empty object, which adds no member, and decodes from any object.
package struct NoMembers: Codable, Sendable, Hashable {
    package init() {}
}
