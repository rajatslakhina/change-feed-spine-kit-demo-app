# ChangeFeedSpine Demo

**A SwiftUI console where you can poison a consumer, flood history past retention, let an AI agent edit your notes — and watch one change stream keep three side systems correct anyway.**

This is the runnable companion to [**change-feed-spine-kit**](https://github.com/rajatslakhina/change-feed-spine-kit), a change-data-capture spine for iOS: one author-tagged history stream fanned out to independent consumer lanes, each with its own durable cursor, back-pressure budget, retry policy, poison quarantine and snapshot rebuild — with the AI agent as a first-class, auditable, undoable transaction author.

The app consumes the library the way a real app would: as a **remote Swift package** (`XCRemoteSwiftPackageReference` → `https://github.com/rajatslakhina/change-feed-spine-kit.git`, rule *Up to Next Major Version* from `1.0.0`, i.e. any `1.x.y ≥ 1.0.0` — a range, not a lock). There is no local path reference and no `branch = main`.

## Why this matters

Delivery semantics are easy to claim and hard to see. A README can say "one slow consumer never blocks the others"; this console lets you make one consumer fail and watch the other two keep moving. Every button exercises a failure mode the library's tests also cover, against the real `ChangeDispatcher` and the real adapters — only the server and the agent are simulated.

## What's on screen

| Section | What it shows |
|---|---|
| **History stream** | Head token, the retention horizon (pruned-through), uploads by author (user / agent / sync), widget reloads |
| **Write as…** | Buttons that commit as `user`, `agent(assistant#N)` or `sync`, inject a poison record, rewrite the agent's text, burst past retention, reset the widget budget, pump or drain |
| **Lanes** | One card per consumer — `sync-outbox`, `search-index`, `widget-reload` — with cursor, lag, health (`idle` / `delivering` / `backoff` / `stalled` / `rebuilding`), applied/skipped counts, rebuilds and quarantined tokens |
| **What did assistant#N change?** | The agent session's net field-level diff, computed from history alone, plus the conflict-checked undo plan and an **Undo agent session** button |
| **Search index lane** | Live query against the index the `search-index` lane maintains |
| **Recent transactions** / **Delivery log** | The raw stream, with author badges, and every non-trivial step outcome |

**On launch** the console is *designed* to seed two notes, have the user save a scratch note, and run one agent session (edit `groceries`, create `summary-1`, delete `scratch-1`) — so the first screen should already show three advanced lanes, an agent diff with one update, one insert and one delete, and a complete undo plan. That is traced in code (`ChangeFeedConsole.task` → `ConsoleModel.start()`); it has **not** been observed on a Simulator — see *Verification*.

Every action runs exclusively: buttons are disabled while one is in flight, because two interleaved actions could show states no single action produces (for example, an audit taken between an agent session's two commits).

## Things to try

1. **Sync pull from server** → the `sync-outbox` lane logs `skipped 1`, and "Uploaded … sync" stays at 0. That is echo-loop prevention by authorship.
2. **Save a malformed note (poison)** → only `search-index` shows a quarantined token; the other lanes advance normally.
3. **User rewrites the agent's text**, then look at the undo plan → one conflict (`groceries.body`) is left alone, and the agent's other changes are still planned for reversal. **Undo agent session** applies that partial plan as one user transaction.
4. **Burst past retention** (do this before spending the widget budget in step 5) → 30 edits are committed before any lane reads them, so history is pruned behind every cursor: each lane logs `rebuilt from snapshot`, the outbox uploads a *full resync* marker, and the agent audit says it is unavailable rather than showing a partial diff. **Agent session** starts a fresh, auditable one.
5. **User edits a note**, repeatedly. Each tap is one `Note` transaction and spends one of the widget lane's 12 reloads (launch spends one). Once they are gone, `widget-reload` reports `backoff`, then `stalled` after three failed attempts, with its lag growing with each further edit — deferred, never dropped. **Reset widget reload budget**, then **Pump lanes once** until the backoff window (at most 8 ticks; one tick per action) has passed; the lane then catches up, coalescing up to four pending transactions (the batch budget) into each reload.

## Design decisions

- **The app owns the policy; the library owns the console.** `DemoApp` builds `ConsoleConfiguration` from the library's own `BatchBudget` and `RetryPolicy` types. That is the shape a real app takes: delivery policy is a product decision, the spine is infrastructure. *Rejected:* hard-coding the numbers inside `ChangeFeedUI`.
- **Deliberately small numbers.** Retention is 24 transactions and the batch budget is 4 transactions / 8 changes, so cursor expiry, back-pressure and stalls are a few taps away. A production app would retain thousands. *Trade-off:* the demo is unrealistic on purpose; the library's tests run the same paths at other sizes.
- **In-memory store instead of SwiftData.** `InMemoryHistoryStore` implements the same `HistorySource` contract a SwiftData `HistoryObserver` adapter would. The demo stays runnable on any iOS 17+ Simulator, and nothing is written to disk. *Rejected:* an iOS 27-only SwiftData adapter that this repo's CI cannot compile.
- **A manual clock, one tick per action.** Backoff deadlines are in ticks, so "wait for the retry window" is something you can step through rather than a race against wall time. *Trade-off:* you pump to make time pass.
- **The widget budget is a transient failure, not dropped work.** Running out of WidgetKit reloads defers the reload and keeps the cursor where it is, so the lane catches up later with coalesced reloads.

## How to run it

1. `git clone https://github.com/rajatslakhina/change-feed-spine-kit-demo-app.git`
2. Open `Demo.xcodeproj` in Xcode 16 or later. Xcode resolves `change-feed-spine-kit` from GitHub (any `1.x` release from `1.0.0`).
3. Select the **Demo** scheme and any iOS 17+ Simulator.
4. Build & Run (⌘R).

## Screenshots

**None exist**, because the app has not been run on a Simulator (see *Verification*). No image in this repository depicts the running app.

## Verification

Two separate facts, stated separately:

- **It builds for the iOS Simulator — verified in CI.** The [Actions](https://github.com/rajatslakhina/change-feed-spine-kit-demo-app/actions) job runs on `macos-15` with Xcode 16.4. It runs `xcodebuild -resolvePackageDependencies`, prints the resulting `Package.resolved` (at the time of writing it resolves `change-feed-spine-kit` **1.0.1**, the newest release inside the `1.0.0 ..< 2.0.0` range, from GitHub), and then runs `xcodebuild build -scheme Demo -destination 'generic/platform=iOS Simulator'`. That proves two things: the remote package reference resolves, and the app compiles against the published library. It does not prove the app launches, or that it behaves as described above.
- **It has not been run on a Simulator.** No one has launched this app on a Simulator or a device. The build ran unattended. Access to the Mac's Xcode and Simulator was available, but Xcode had another, unrelated project open, so the run was not attempted, to avoid interfering with that work. Everything under *What's on screen* and *Things to try* comes from tracing the code (`ConsoleModel`, `ChangeFeedConsole`) by hand, plus the library's 55 passing tests. None of it has been observed on screen. **No screenshots exist.**

The library's own verification (local build and tests, Linux + macOS CI, mutation checks) is described in its [README](https://github.com/rajatslakhina/change-feed-spine-kit#verification).

## License

MIT
