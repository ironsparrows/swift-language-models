/// Reasoning effort types: ``Of`` for a model of a provider module's catalog, and ``Unsupported`` for a model described
/// by hand whose level can't be chosen.
///
/// ``Of`` offers exactly the levels its model accepts, so code can name only those, and keeps a level the model stopped
/// accepting as a deprecated member.
public enum Efforts {}
