# Milestone 4: KataGo Analysis Process Boundary

Status: proposal. Follows the app shells landed in
`docs/designs/milestone-3-app-bundles.md` and the engine stubs in
`Sources/GokanEngine/`.

Scope: define and ship the **first compilable** version of a GPL-compliant
KataGo analysis-mode boundary in `GokanEngine`, behind the existing
`GoAnalysisEngine` protocol, without bundling KataGo or changing the public
analysis types. Out of scope: building/shipping a KataGo binary, model
distribution, Apple Silicon fork work, iOS in-process engine, GTP, SGF
streaming.

## Why now

`KataGoAnalysisEngine` currently delegates to `MockAnalysisEngine`
(`Sources/GokanEngine/KataGoEngineConfiguration.swift`). The SwiftUI shell
and app bundles are in place, so the next useful slice is a real
`analysis`-mode adapter that:

- compiles today on iOS and macOS without a KataGo binary present;
- has a tested JSON line protocol layer;
- runs end-to-end against a `katago analysis` subprocess on macOS when one
  is configured locally;
- fails cleanly (and visibly) on iOS, where subprocess spawning is
  unavailable.

Landing the protocol layer first means the future Apple Silicon fork and
iOS embedded path become drop-in replacements behind the same Swift
protocol, with no UI churn.

## Constraints and non-goals

- **No bundled KataGo.** `engine/KataGo/` stays gitignored
  (`LICENSE_POLICY.md`, `docs/compliance.md`). The package must build and
  test from a clean checkout with no engine binary present.
- **GPL hygiene.** Every new file gets
  `// SPDX-License-Identifier: GPL-3.0-or-later`. Nothing in this milestone
  imports KataGo headers or copies KataGo source. The JSON schema is
  re-implemented from the public KataGo analysis protocol docs; cite the
  upstream doc URL in each schema file header rather than copying text.
- **Public types stay stable.** `AnalysisRequest`, `AnalysisSnapshot`,
  `CandidateMove`, and `GoAnalysisEngine` keep their current shape so the
  UI and tests are untouched.
- **No new SwiftPM dependencies.** Foundation + GokanCore only. JSON
  encoding/decoding uses `JSONEncoder` / `JSONDecoder`.

## Protocol shape

The public surface stays the same `GoAnalysisEngine` protocol. Internally,
`GokanEngine` grows two collaborators behind `KataGoAnalysisEngine`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Codec for the KataGo `analysis` line protocol. Pure value types,
// no I/O. Reference: KataGo docs/Analysis_Engine.md (cite, do not copy).
internal struct KataGoAnalysisCodec {
    func encode(_ request: AnalysisRequest, id: String) throws -> Data        // single JSON line
    func decode(_ line: Data) throws -> KataGoAnalysisResponse                 // one response line
    func snapshot(from response: KataGoAnalysisResponse) -> AnalysisSnapshot   // map -> public type
}

// Transport that pumps JSON lines to/from a KataGo `analysis` process.
// Implemented only where Foundation.Process is available (macOS).
internal protocol KataGoTransport: Sendable {
    func start() async throws
    func send(_ line: Data) async throws
    func responses() -> AsyncThrowingStream<Data, Error>                       // one element per stdout line
    func stop() async
}
```

`KataGoAnalysisEngine.analyze(_:)` becomes:

1. resolve a `KataGoTransport` for the current platform (factory below);
2. assign a per-request `id` (UUID string) and encode the request;
3. write the line to stdin; read response lines and filter by `id`;
4. translate each response into `AnalysisSnapshot` and yield it on the
   public `AsyncThrowingStream`;
5. finish the stream on `isDuringSearch == false` (terminal response) or
   on transport error;
6. on cancellation, send the matching `action: "terminate"` line and stop
   the transport.

Concurrency: `KataGoAnalysisEngine` owns one transport per engine
instance; concurrent requests are multiplexed by request `id` rather than
serialized in Swift, which matches KataGo's analysis-mode semantics.

## JSON line request/response handling

Request shape (subset, enough to compile and test today):

```json
{
  "id": "<uuid>",
  "rules": "japanese",
  "komi": 6.5,
  "boardXSize": 19,
  "boardYSize": 19,
  "initialPlayer": "B",
  "initialStones": [["B","Q16"], ["W","D4"]],
  "moves": [["B","Q4"], ["W","D16"]],
  "maxVisits": 400,
  "includePolicy": true,
  "includeOwnership": false
}
```

Response shape (subset we map onto `AnalysisSnapshot`):

```json
{
  "id": "<uuid>",
  "isDuringSearch": true,
  "rootInfo": { "winrate": 0.52, "scoreLead": -0.4, "visits": 137 },
  "moveInfos": [
    { "move": "Q3", "winrate": 0.55, "prior": 0.31, "visits": 60 },
    ...
  ]
}
```

Mapping rules:

- `CandidateMove.point` ← KataGo move string parsed through a new internal
  `KataGoCoordinates` helper (A1-style, skipping `I`). This lives next to
  `SGFCoordinates` in `GokanCore` only if `GokanEngine` needs it publicly;
  for milestone 4 it stays `internal` to `GokanEngine`.
- `policy` ← `moveInfos[].prior`.
- `winRate` ← `moveInfos[].winrate`.
- `visits` ← `moveInfos[].visits`.
- `AnalysisSnapshot.scoreLead` ← `rootInfo.scoreLead`.
- `AnalysisSnapshot.completedVisits` ← `rootInfo.visits`.

`AsyncThrowingStream` continuation yields one snapshot per response line
until `isDuringSearch == false`, then finishes. Unknown fields are
ignored so upstream protocol additions do not break the codec.

## Subprocess where available

Add a transport implementation for macOS only, behind a platform guard:

```swift
#if os(macOS)
internal final class ProcessKataGoTransport: KataGoTransport { ... }
#endif

internal enum KataGoTransportFactory {
    static func make(for configuration: KataGoEngineConfiguration) throws -> KataGoTransport {
        #if os(macOS)
        return ProcessKataGoTransport(configuration: configuration)
        #else
        throw KataGoEngineError.platformUnsupported
        #endif
    }
}
```

`ProcessKataGoTransport` uses `Foundation.Process` with:

- `executableURL = configuration.executableURL`;
- `arguments = ["analysis", "-model", modelURL.path, "-config", configURL.path]`;
- piped stdin/stdout/stderr;
- a stdout reader that splits on `\n` and forwards each line to the
  `responses()` stream;
- a stderr reader that surfaces lines via `os.Logger` and discards them
  from the protocol path.

Startup is lazy: the process spawns on the first `analyze(_:)` call and
shuts down on `stop()` or `deinit`. A small `engineReady` task waits for
KataGo's "Started, ready to begin handling requests" stderr banner (or a
short timeout) before forwarding the first request, so users see a clean
error instead of a silent hang when the binary or model is wrong.

## iOS limitations

iOS has no `Foundation.Process`. The milestone-4 iOS path is:

- `KataGoTransportFactory.make` throws `KataGoEngineError.platformUnsupported`;
- `KataGoAnalysisEngine.analyze(_:)` surfaces that error on the
  `AsyncThrowingStream`;
- The UI continues to default to `MockAnalysisEngine` on iOS (engine
  selector in the SwiftUI shell already shows "KataGo (not configured)" —
  reuse that affordance with a clearer message: "KataGo analysis is not
  available on iOS in this build").

No iOS code paths attempt `Process`, `Posix.fork`, `system`, or any
sandbox-violating syscall. The protocol layer (`KataGoAnalysisCodec`) is
platform-neutral and compiles on iOS so that the future embedded library
path can reuse it untouched.

## Errors

Add a public error type so the UI can show actionable messages without
parsing strings:

```swift
public enum KataGoEngineError: Error, Sendable {
    case platformUnsupported
    case executableMissing(URL)
    case modelMissing(URL)
    case configMissing(URL)
    case startupFailed(underlying: Error)
    case protocolViolation(reason: String)
    case engineTerminated(exitCode: Int32, stderrTail: String)
}
```

Resolution rules:

- All three URLs in `KataGoEngineConfiguration` are validated with
  `FileManager.default.fileExists(atPath:)` before spawning. Missing
  paths produce specific cases above.
- JSON decode failures map to `.protocolViolation`. The malformed line is
  truncated to ~512 bytes for the message to keep logs bounded.
- Non-zero process exit becomes `.engineTerminated` with the last 4 KB of
  stderr.

## Tests

All tests live in `Tests/GokanEngineTests/`. None of them require a real
KataGo binary; the macOS subprocess path is exercised against a tiny
scripted helper.

1. **Codec round-trip** (`KataGoAnalysisCodecTests.swift`)
   - Encodes an `AnalysisRequest` for a 9×9 empty board with one B move
     and asserts canonical JSON fields (`boardXSize`, `moves`, `rules`,
     `maxVisits`).
   - Decodes a recorded `moveInfos` payload (fixture under
     `Tests/Fixtures/katago/analysis_response.jsonl`) and asserts the
     resulting `AnalysisSnapshot` has the expected
     `candidateMoves.count`, `scoreLead`, and `completedVisits`.
   - Decodes a streaming sequence (multiple lines, last with
     `isDuringSearch == false`) and asserts the snapshot stream
     terminates on the final line.

2. **Coordinate mapping** (`KataGoCoordinatesTests.swift`)
   - Parses `A1`, `T19`, and `Q4`; asserts mapping to `BoardPoint`
     and back. Asserts `I` is skipped (KataGo's column convention).

3. **Error mapping** (`KataGoEngineErrorTests.swift`)
   - Missing executable / model / config URLs each map to the correct
     case via the validator helper, with `Process` never spawned.
   - Malformed JSON line produces `.protocolViolation`.

4. **Scripted transport** (`ScriptedKataGoTransportTests.swift`)
   - Injects a `KataGoTransport` test double that replays a recorded
     JSONL session for a single request id.
   - Asserts `KataGoAnalysisEngine` yields N snapshots in order and
     finishes the stream when the recording ends.
   - Cancels the consuming `Task` mid-stream and asserts the transport
     receives a `terminate` line for the matching id.

5. **macOS subprocess smoke test** (`ProcessKataGoTransportTests.swift`,
   guarded by `#if os(macOS)` and `#if canImport(Foundation.Process)`)
   - Spawns `/bin/cat` (not KataGo) as the "executable" and asserts
     that lines written to stdin appear on the `responses()` stream
     unchanged. Validates the line-splitter, stdin pipe, and stdout
     reader without depending on KataGo being installed.
   - Marked `.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil)`
     only if CI flakes; default is enabled.

6. **Existing `MockAnalysisEngineTests` stays untouched** — the public
   protocol is unchanged.

Fixtures live under `Tests/GokanEngineTests/Fixtures/katago/` and are
hand-authored JSONL trimmed to the fields we decode. No KataGo source is
copied.

## File-by-file plan (still no source edits in this PR)

```text
Sources/GokanEngine/
  KataGoAnalysisCodec.swift           // encode/decode + snapshot mapper
  KataGoAnalysisProtocol.swift        // request/response Codable structs (subset)
  KataGoCoordinates.swift             // internal A1<->BoardPoint helper
  KataGoEngineError.swift             // public error enum
  KataGoTransport.swift               // protocol + factory
  ProcessKataGoTransport.swift        // #if os(macOS) implementation
  KataGoAnalysisEngine.swift          // moved out of KataGoEngineConfiguration.swift
                                      // now uses codec + transport

Tests/GokanEngineTests/
  KataGoAnalysisCodecTests.swift
  KataGoCoordinatesTests.swift
  KataGoEngineErrorTests.swift
  ScriptedKataGoTransportTests.swift
  ProcessKataGoTransportTests.swift   // #if os(macOS)
  Fixtures/katago/
    analysis_response.jsonl
    streaming_response.jsonl
```

`KataGoEngineConfiguration.swift` keeps only the configuration struct;
the engine moves to its own file so the diff in milestone-5 (fork hooks)
is small.

## Future Apple Silicon fork hooks

The milestone-4 boundary is intentionally minimal so the Apple Silicon
fork work in `docs/katago-apple-silicon-roadmap.md` can land additively:

- `KataGoEngineConfiguration` gains a `backend: Backend` field
  (`.metalUpstream`, `.metalFork`, `.embedded`) in a later milestone.
  The factory switches transports on that field. No public API change.
- `KataGoTransport` is the seam for the iOS embedded library: a future
  `EmbeddedKataGoTransport` implements the same protocol over a thin
  C/C++ bridge instead of stdin/stdout. The codec, error type, and
  snapshot mapping are reused as-is.
- Benchmark-friendly hooks: add a non-public
  `KataGoAnalysisEngine.timings` accessor in a follow-up so the
  benchmark scripts in `scripts/benchmark-katago-metal.sh` can correlate
  Swift-side latency with engine-side `visits/sec`. Out of scope here
  but the codec already carries `rootInfo.visits` per response, which is
  the input the benchmark needs.
- Model catalog (`GokanModels` in `docs/architecture.md`) is unaffected;
  this milestone treats the model file as an opaque URL.

## Verification

```sh
# Builds on both platforms with no KataGo binary present.
swift build
swift test                                                # all milestone-4 tests

# Optional, manual, only when a local KataGo is available:
export GOKAN_KATAGO_EXECUTABLE=/usr/local/bin/katago
export GOKAN_KATAGO_MODEL=$HOME/katago/model.bin.gz
export GOKAN_KATAGO_CONFIG=$HOME/katago/analysis.cfg
swift test --filter ProcessKataGoTransportTests           # cat-based smoke only
```

The done-criterion for Milestone 4 is: `swift build` and `swift test`
green on macOS and on the iOS Simulator from a clean checkout, with no
KataGo binary present; the SwiftUI shell still defaults to
`MockAnalysisEngine` and reports `.platformUnsupported` cleanly when the
user selects "KataGo" on iOS.

## Risks and follow-ups

- **Protocol drift.** KataGo's analysis protocol evolves. Mitigation:
  fixtures + unknown-field tolerance + a single codec module so updates
  are localized. Pin the documented schema version in
  `KataGoAnalysisProtocol.swift`'s file header.
- **Sandbox interactions on macOS.** App Sandbox is off in milestone 3.
  When it lands, spawning an arbitrary `katago` executable will need
  `com.apple.security.inherit` or a helper-tool architecture. Track in
  the sandbox follow-up, not here.
- **iOS expectations.** Surfacing `.platformUnsupported` in the UI is a
  placeholder. The real iOS story (embedded library + reduced model)
  starts after the Apple Silicon Metal baseline is profiled per
  `docs/katago-apple-silicon-roadmap.md`.
- **No process cleanup on crash.** If the app crashes, a stray `katago`
  may linger. A later milestone can add a small launchd helper or a
  `PR_SET_PDEATHSIG`-equivalent on macOS (`posix_spawn` attribute) — out
  of scope for the first compilable slice.
