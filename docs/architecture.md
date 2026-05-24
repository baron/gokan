# Architecture

## Goals

- One app codebase for iOS, iPadOS, and macOS.
- Native-feeling SwiftUI interface, not a web wrapper.
- Strong offline analysis when hardware allows.
- Engine integration that can swap between upstream KataGo, the Apple Silicon
  fork, and test doubles.

## Proposed Modules

```text
GokanApp
  SwiftUI scenes, navigation, documents, settings, platform glue

GokanCore
  Board state, moves, rules, coordinates, scoring helpers, SGF model

GokanEngine
  Engine protocol, analysis streams, KataGo JSON/GTP adapters, process control

GokanKataBridge
  Thin boundary to the KataGo executable or embedded C++ entry points

GokanModels
  Model catalog, download verification, cache management, device profiles
```

## Engine Boundary

Start with a process boundary on macOS:

- Build `katago` with `USE_BACKEND=METAL`.
- Launch it in `analysis` mode from the app.
- Communicate using KataGo's JSON analysis protocol.
- Stream partial analysis into Swift async sequences.

This keeps the first app stable while the fork changes underneath it. For iOS,
the process boundary is usually unavailable, so the later choice is either:

- embedded engine library with a public C/C++ facade, or
- a reduced on-device engine path with a smaller model and direct Metal/Core ML
  inference integration.

## Data Flow

```text
SwiftUI board
  -> GokanCore game state
  -> GokanEngine request
  -> KataGo analysis
  -> streamed policy/ownership/score results
  -> SwiftUI overlays
```

## Performance Principle

Do not fork for guesses. Fork for measured bottlenecks:

- baseline upstream Metal backend;
- collect benchmark output and Instruments traces;
- improve one bottleneck at a time;
- keep upstream-compatible patches small enough to submit back when possible.
