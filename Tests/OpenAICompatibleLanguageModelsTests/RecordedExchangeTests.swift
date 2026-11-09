import Testing

/// Exchanges replayed from what Gemini, Groq and Ollama really sent through the package, with the statuses and headers
/// they sent, so these pin how real streams and failures read. Ids and what shows the account are swapped for fake
/// values; thought signatures and reasoning stay as they came.
@Suite("Recorded exchanges", .timeLimit(.minutes(1)))
struct RecordedExchangeTests {}
