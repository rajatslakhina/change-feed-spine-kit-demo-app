import SwiftUI
import ChangeFeed
import ChangeFeedUI

/// The demo app owns the delivery policy; the library's console only runs it.
///
/// The numbers are deliberately small so every failure mode is reachable in a few taps:
/// a 4-transaction / 8-change batch budget makes back-pressure visible, a 24-transaction
/// retention window means "Burst past retention" prunes history behind every cursor and
/// forces a snapshot rebuild, and `stallAfter: 3` lets the widget lane go from
/// "backoff" to "stalled" once its reload budget is spent.
@main
struct DemoApp: App {
    private let configuration = ConsoleConfiguration(
        budget: BatchBudget(maxTransactions: 4, maxChanges: 8),
        retry: RetryPolicy(baseDelay: 1, maxDelay: 8, stallAfter: 3, deadLetterCapacity: 20),
        retention: 24,
        agentSessionPrefix: "assistant"
    )

    var body: some Scene {
        WindowGroup {
            ChangeFeedConsole(configuration: configuration)
        }
    }
}
