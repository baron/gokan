# Milestones 1–2: GokanCore and SwiftUI Shell

Status: proposal, partially implemented by the initial SwiftPM slice.
Scope: the next two buildable milestones only — a shared Swift `GokanCore`
package and a dual-platform SwiftUI app shell that talks to a placeholder
engine. KataGo build, fork, and real engine wiring are deliberately out of
scope here; they remain on the existing roadmap under `docs/architecture.md`
and `docs/katago-apple-silicon-roadmap.md`.

## Context and Constraints

Original repo state at planning time (see `README.md`, `docs/architecture.md`):

- Only docs, scripts, and license/notice files existed. The first implementation
  slice now adds a root Swift package with `GokanCore`, `GokanEngine`,
  `GokanUI`, and a `GokanMacApp` executable target.
- Target platforms: iOS, iPadOS, macOS, one SwiftUI codebase.
- Planned module split: `GokanApp`, `GokanCore`, `GokanEngine`,
  `GokanKataBridge`, `GokanModels`.
- License posture (`LICENSE_POLICY.md`, `docs/compliance.md`):
  - Original Gokan code is GPL-3.0-or-later with SPDX headers.
  - KataGo-derived code keeps its upstream MIT-style license and notices.
  - The KataGo checkout lives under `engine/KataGo/` and is gitignored.
- Naming (`docs/naming.md`): use `Gokan` for code, packages, bundle IDs;
  reserve `Gokan 碁冠` for branding surfaces only.

Design implications for these two milestones:

1. Nothing in `GokanCore` or the SwiftUI shell may import KataGo headers,
   link KataGo, or copy KataGo source. The engine boundary in this phase is
   a Swift protocol with a fake implementation.
2. All new source files get the GPL-3.0-or-later SPDX header.
3. Module/package names use `Gokan` (not `GoKan`, not `gokan-core`).
4. The repo layout in `README.md` (`app/`, `packages/`, `engine/`,
   `models/`) is the target; these milestones land `packages/` and `app/`.

## Milestone 1 — `GokanCore` Swift Package

Goal: a pure-Swift, dependency-free package that models a Go game well
enough for the SwiftUI shell to render, edit, navigate, and round-trip SGF.
No engine, no networking, no Apple-only frameworks. Must build for iOS,
macOS, and `swift test` from the command line on Apple Silicon.

### Package shape

```text
packages/GokanCore/
  Package.swift                 // swift-tools-version: 5.10, platforms iOS 17 / macOS 14
  Sources/GokanCore/
    Board/
      Color.swift               // Stone color, opponent()
      Point.swift               // (col,row), conversions, A1/sgf coords
      BoardSize.swift           // 9/13/19 + arbitrary square sizes
      Board.swift               // packed [UInt8] grid, immutable value type
      Neighbors.swift           // 4-neighborhood, group flood fill
    Rules/
      Ruleset.swift             // Japanese / Chinese / AGA stub (scoring only)
      MoveResult.swift          // legal | suicide | ko | superko | offBoard
      Position.swift            // Board + ko state + side to move + captures
      MoveValidator.swift       // legality + capture resolution
      SuperkoTracker.swift      // positional/situational superko
    Game/
      GameTree.swift            // SGF-style tree with main line + variations
      GameNode.swift            // move, comments, marks, properties
      GameRecord.swift          // metadata (players, rank, komi, result)
      Coordinates.swift         // SGF <-> human-readable mapping
    SGF/
      SGFLexer.swift
      SGFParser.swift           // strict subset: FF[4], GM[1]
      SGFWriter.swift
      SGFProperty.swift
    Scoring/
      AreaScorer.swift          // simple area scoring (Chinese-style)
      TerritoryScorer.swift     // territory scoring with dead-stone hints
    Analysis/
      AnalysisSnapshot.swift    // pure value types the engine layer will fill
      MoveAnnotation.swift      // policy %, winrate, score lead, ownership grid
  Tests/GokanCoreTests/
    BoardTests.swift
    RulesTests.swift            // capture, suicide, simple ko, positional superko
    SGFRoundTripTests.swift     // load + save fixtures from Tests/Fixtures
    ScoringTests.swift
    GameTreeTests.swift         // variation navigation, undo/redo semantics
    Fixtures/                   // small public-domain SGFs only
```

### Key design choices

- **Value-type board.** `Board` and `Position` are `struct` with copy-on-write
  storage so SwiftUI views can hold snapshots without locking. The grid is
  `ContiguousArray<UInt8>` for cache-friendly iteration.
- **Pure functions for rules.** `MoveValidator.apply(_:to:)` returns
  `Result<Position, MoveResult>` — no exceptions, no mutation of inputs.
  Makes engine integration and undo trivial.
- **Superko via Zobrist hashing.** `SuperkoTracker` keeps a `Set<UInt64>`
  of seen positions. Hash table is pre-seeded so two `Position` values
  produce identical hashes across processes (important for future engine
  cross-checks).
- **SGF first, GTP later.** Milestone 1 ships SGF (load/save/edit). GTP I/O
  belongs to `GokanEngine` and arrives with milestone 2's placeholder.
- **No UIKit/AppKit imports.** `GokanCore` only imports `Foundation`. UI
  affordances (colors, paths) live in the app target.
- **Analysis types but no engine.** `AnalysisSnapshot` and friends exist so
  the SwiftUI shell can render fake overlays today and real ones tomorrow
  without API churn.

### Done criteria for Milestone 1

- `swift build` and `swift test` pass on macOS 14 / Xcode 16 from a clean
  checkout.
- Rules tests cover: capture, suicide rejection, simple ko, positional
  superko, pass, two-pass game end.
- SGF round-trip is byte-identical for the bundled fixture set (modulo
  documented normalization).
- Public API has doc comments and is reviewed for source stability — once
  the SwiftUI shell ships in milestone 2, breaking changes here become
  expensive.
- Every new file carries `// SPDX-License-Identifier: GPL-3.0-or-later`.

### Out of scope for Milestone 1

- Estimating dead stones, life-and-death solvers.
- Joseki dictionaries.
- Cloud sync, iCloud documents.
- Any KataGo header, library, or process.

## Milestone 2 — SwiftUI Shell + Placeholder Engine Boundary

Goal: a runnable Gokan app on iOS Simulator and macOS that opens an SGF,
displays the board, plays/undoes moves, navigates the game tree, and shows
fake analysis overlays driven by a `MockEngine`. The real KataGo bring-up
stays on the existing roadmap and is unblocked by the protocol landed here.

### Target layout

```text
app/
  Gokan.xcodeproj                 // or Gokan.xcworkspace if we keep SwiftPM-only
  Gokan/                          // shared SwiftUI target (iOS + macOS)
    GokanApp.swift                // @main, Scene composition
    Documents/
      GokanDocument.swift         // FileDocument wrapping SGF text
      DocumentBrowser.swift       // iOS document browser entry
    Scenes/
      BoardScene.swift            // board + side panel layout
      GameTreeScene.swift         // variation tree pane
      AnalysisScene.swift         // engine overlays toggles
    Views/
      BoardView.swift             // Canvas-based renderer
      StoneLayer.swift
      AnnotationsLayer.swift      // last-move marker, marks, numbers
      AnalysisOverlay.swift       // policy heatmap, winrate bar
      MoveListView.swift
      EngineStatusBadge.swift
    ViewModels/
      GameViewModel.swift         // @Observable wrapper over GokanCore
      AnalysisViewModel.swift     // subscribes to EngineSession
    Platform/
      KeyCommands.swift           // macOS keyboard shortcuts
      Haptics.swift               // iOS only, guarded by #if os(iOS)
  GokanTests/
    GameViewModelTests.swift
    MockEngineTests.swift
  GokanUITests/
    SmokeTests.swift              // launch, open fixture SGF, play a move

packages/GokanEngine/             // separate SwiftPM package, no KataGo deps
  Sources/GokanEngine/
    EngineProtocol.swift          // public protocol surface
    AnalysisRequest.swift
    AnalysisEvent.swift
    EngineSession.swift           // AsyncSequence stream wrapper
    MockEngine/
      MockEngine.swift            // deterministic fake for tests + previews
      ScriptedResponses.swift
    Process/                      // placeholder; empty in milestone 2 except for
      ProcessEngine.swift         // a no-op stub that throws .notConfigured
  Tests/GokanEngineTests/
    MockEngineTests.swift
    StreamingTests.swift
```

### Engine boundary (the important part)

Keep the surface tiny so KataGo work in later milestones is purely additive.

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
public protocol Engine: Sendable {
    var info: EngineInfo { get }
    func start() async throws
    func stop() async
    func analyze(_ request: AnalysisRequest) -> AsyncThrowingStream<AnalysisEvent, Error>
}

public struct AnalysisRequest: Sendable, Hashable {
    public var position: Position          // from GokanCore
    public var maxVisits: Int
    public var maxTimeSeconds: Double?
    public var includeOwnership: Bool
    public var includePolicy: Bool
}

public enum AnalysisEvent: Sendable {
    case partial(AnalysisSnapshot)         // from GokanCore
    case final(AnalysisSnapshot)
    case error(EngineError)
}
```

Why this shape:

- `AsyncThrowingStream` matches KataGo's analysis protocol naturally:
  partial updates as visits accumulate, then a final snapshot.
- `Position` and `AnalysisSnapshot` are owned by `GokanCore`, so swapping
  `MockEngine` for the future `KataGoProcessEngine` does not touch the UI.
- `Sendable` everywhere lets the app run engines off-actor without
  retrofitting concurrency later.
- No KataGo types leak into the protocol. The future `GokanKataBridge`
  package will live behind this protocol and never appear in `GokanApp`
  imports.

`MockEngine` returns plausible-looking but obviously synthetic data
(uniform-ish policy with a bias toward the corners, oscillating winrate)
so that visual regressions are caught while real engine bring-up proceeds
in parallel.

### App-level deliverables

- Board renders at 9×9, 13×13, 19×19. Tap/click places a stone; right-click
  / long-press shows a context menu (mark, comment, branch).
- Document model wraps SGF: opening a `.sgf` file on macOS or via the iOS
  document browser produces a live `GameViewModel`.
- Game-tree pane navigates main line and variations; arrow keys on macOS,
  swipe gestures on iOS.
- Analysis pane has an on/off toggle that wires `GameViewModel` to an
  `EngineSession` backed by `MockEngine`. UI shows winrate bar, score lead,
  top-N candidate moves with policy %, and a heatmap toggle.
- Settings scene exposes engine selection (`Mock`, `KataGo (not configured)`)
  to prove the selector exists; selecting KataGo surfaces a friendly
  "engine not yet available" message.
- Smoke UI test opens a bundled fixture SGF and plays one move on both
  destinations.

### Done criteria for Milestone 2

- `xcodebuild` builds and runs on iOS Simulator (iPhone 15, iPad Pro) and
  macOS (Apple Silicon) from a clean checkout.
- App opens a fixture SGF, plays/undoes moves, switches variations, and
  shows mock analysis overlays without dropping frames in Instruments
  Time Profiler at 60 Hz on an M-series Mac.
- `MockEngine` covers happy path, cancellation, and error injection in
  unit tests.
- `KataGoProcessEngine` exists only as a stub that throws
  `EngineError.notConfigured`. No KataGo source, no `engine/KataGo/`
  dependency.
- Bundle identifiers, target names, and scheme names use `Gokan`
  (per `docs/naming.md`).

## License Hygiene Checklist for Both Milestones

- Every new `.swift` file starts with
  `// SPDX-License-Identifier: GPL-3.0-or-later`.
- `Package.swift` files declare no KataGo dependencies in these milestones.
- No source under `packages/` or `app/` is copied from KataGo or any
  upstream project. Where Go-rules logic is informed by published rule
  sets, cite the source in the file header rather than copying code.
- `THIRD_PARTY_NOTICES.md` does not need changes for these milestones
  (no new third-party code is bundled). If we add a Swift dependency,
  update it in the same PR.
- `engine/KataGo/` and `engine/build-*/` remain gitignored.

## Suggested PR Sequence

1. `chore: add packages/GokanCore skeleton + Package.swift` (empty types,
   GPL headers, CI placeholder).
2. `feat(core): board, point, color, position value types + tests`.
3. `feat(core): move legality, captures, ko, superko + tests`.
4. `feat(core): SGF lexer/parser/writer + round-trip fixtures`.
5. `feat(core): area + territory scoring + tests` — closes Milestone 1.
6. `chore: add packages/GokanEngine with Engine protocol + MockEngine`.
7. `chore: add app/Gokan SwiftUI shell, multi-platform target`.
8. `feat(app): board view, document model, game tree pane`.
9. `feat(app): analysis overlay wired to MockEngine` — closes Milestone 2.

Each PR is independently reviewable and leaves `main` buildable. After
Milestone 2 lands, the existing KataGo roadmap picks up from the
`KataGoProcessEngine` stub.

## Risks and Open Questions

- **SwiftPM vs Xcode project.** Pure SwiftPM is simplest for `GokanCore`;
  the app likely needs an `xcodeproj` for entitlements, assets, and
  per-platform Info.plist. Recommendation: SwiftPM for packages, an
  Xcode project for `app/Gokan` that depends on the local packages.
- **Concurrency model.** `@Observable` (Swift 5.9+) is preferred over
  `ObservableObject` to minimise SwiftUI invalidation churn during
  streaming analysis. Confirms minimum deployment targets: iOS 17,
  macOS 14.
- **Document architecture on iOS.** `FileDocument` works on both
  platforms but iOS document browser ergonomics differ; budget a small
  spike inside Milestone 2.
- **GPL + App Store.** Out of scope for these milestones but flagged in
  `docs/compliance.md`. The placeholder engine boundary keeps this
  decision deferrable.

## What This Plan Deliberately Does Not Do

- No KataGo build, fork, or benchmark work — that lives in
  `docs/katago-apple-silicon-roadmap.md` and starts after Milestone 2.
- No Core ML or on-device inference path.
- No cloud features, no accounts, no telemetry.
- No design system or visual identity beyond stock SwiftUI styling; a
  separate design pass should come after the shell is real.
