# Gokan

Open-source Go analysis and play application targeting iOS and macOS, powered by
KataGo.

## Name

The official project name is **Gokan**.

The full mark is **Gokan 碁冠**, read as "Go crown." The romanized app name
should be used for ordinary English UI, repositories, packages, and command-line
tools; the full mark is reserved for branding, about screens, documentation
headers, and release materials.

## Direction

- Native SwiftUI app for iOS, iPadOS, and macOS.
- Shared Swift package for board state, SGF parsing, engine orchestration, model
  catalog metadata, and app settings.
- KataGo integrated as a separately tracked engine fork, preserving upstream
  license notices.
- Apple Silicon performance work focused first on the existing KataGo Metal
  backend, then on measured bottlenecks in search, batching, memory movement,
  and model loading.

## Repository Layout

```text
app/              SwiftUI app targets
packages/         Shared Swift packages
engine/           KataGo fork or submodule
models/           Download/cache metadata only, not large checked-in models
docs/             Architecture, compliance, and performance notes
scripts/          Build, benchmark, and packaging helpers
```

## First Milestones

1. Build KataGo's Metal backend locally on Apple Silicon and record baseline
   benchmarks.
2. Wrap the engine behind a stable local process/API boundary on macOS.
3. Prototype the iOS engine path, deciding whether to embed KataGo code directly
   or use an app-local service abstraction with a smaller model profile.
4. Build the shared board, SGF, and analysis UI shell.
5. Start performance work only after benchmark traces identify the slowest
   Apple Silicon paths.

## Local Setup

```sh
scripts/check-toolchain.sh
swift test
scripts/fetch-katago.sh
scripts/build-katago-metal.sh
```

KataGo's Metal backend requires CMake, Ninja, Xcode, and Swift/C++ interop.
The Swift package builds the shared core, model metadata/cache helpers, KataGo
analysis boundary, SwiftUI shell, and macOS executable target.

### Model profiles and cache

Model profiles are metadata only. Gokan does not download or bundle KataGo
neural network files in this repository. When a catalog-enabled build selects a
profile, place user-provided files under:

```text
<cacheRoot>/models/<modelFileName>
<cacheRoot>/configs/<defaultConfigFileName>
```

The app can show local cache readiness and verify SHA-256 checksums when profile
metadata includes one. Manual KataGo model/config paths remain available and
take precedence over selected profiles.

Run the macOS development app:

```sh
swift run GokanMacApp
```

## Licensing Posture

Copyright 2026 Gokan contributors.

Gokan's original app code is licensed as GPL-3.0-or-later. KataGo-derived code,
KataGo vendored dependencies, and KataGo neural network files keep their own
upstream licenses and notices. See [LICENSE](LICENSE),
[LICENSE_POLICY.md](LICENSE_POLICY.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md),
and [docs/compliance.md](docs/compliance.md).

Model catalog entries track local file names, checksums, and license notice
metadata only. Neural network binaries should live outside git or under ignored
cache directories.

App Store distribution needs a separate legal decision because GPL-family
licenses and Apple's distribution terms can conflict.
