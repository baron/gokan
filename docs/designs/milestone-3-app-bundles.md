# Milestone 3: Real iOS and macOS App Bundles

Status: proposal. Follows the SwiftPM shell landed in
`docs/designs/milestone-1-2-plan.md`.

Scope: stand up genuine `Gokan.app` bundles for iOS and macOS that link
the existing `GokanCore`, `GokanEngine`, and `GokanUI` SwiftPM libraries
without duplicating their source. Out of scope: KataGo bring-up,
entitlements for sandboxed distribution, App Store submission, CI
signing, asset/icon design.

## Why we need bundle targets

The current `GokanMacApp` SwiftPM executable runs from `swift run`, but a
pure SwiftPM executable cannot produce a real `.app`:

- No `Info.plist` (`CFBundleIdentifier`, `UIDeviceFamily`,
  `LSApplicationCategoryType`, scene manifests).
- No asset catalog, no app icon, no launch storyboard / iOS scene config.
- No code signing or entitlements (`com.apple.security.app-sandbox`,
  `com.apple.developer.kernel.extended-virtual-addressing` later for
  KataGo).
- No iOS support at all — SwiftPM `executableTarget` is macOS-only when
  invoked via `swift run`, and `xcodebuild` cannot package it as an
  iOS app.

Milestone 3 fixes this without breaking the package layout: the libraries
stay as SwiftPM products, and only the app shells move into an Xcode
project.

## Options Considered

### A. Hand-authored `Gokan.xcodeproj` checked into git

Pros: zero new tooling; works with stock Xcode; easiest path for
contributors who already use Xcode; signing UI lives where developers
expect it.

Cons: `project.pbxproj` is noisy and merge-hostile; easy to drift between
iOS and macOS targets; manual upkeep when adding files or build settings;
two-developer edits collide.

### B. Generated project via XcodeGen

Pros: human-readable YAML (`project.yml`); regeneratable; trivial to keep
iOS and macOS targets in lockstep; well-understood by the Swift community;
single binary dependency (`brew install xcodegen`).

Cons: extra tool in the contributor setup; project must be regenerated
after spec changes; some advanced Xcode features (signing capability UI)
still require opening the generated project.

### C. Generated workspace via Tuist

Pros: strongest support for multi-platform, multi-target projects;
manifest is Swift, so it composes with our SwiftPM packages; first-class
caching.

Cons: heavier dependency (Tuist daemon, manifest compilation); steeper
learning curve; overkill for two app targets and three libraries.

### D. SwiftPM only, no Xcode project

Pros: nothing new to learn.

Cons: cannot produce an iOS `.app` at all; cannot attach entitlements;
asset catalogs and Info.plist support in SwiftPM are too limited for a
real shipping app. Non-starter for the iOS deliverable.

## Recommendation

Go with **Option B (XcodeGen)**. It keeps `project.pbxproj` out of code
review, scales to the iOS + macOS pair we need today, and leaves the door
open to switch to Tuist later if the project grows. Hand-authoring (A) is
acceptable as a fallback if we want zero new tooling, but the
maintenance tax shows up the first time two PRs touch the project file.

### Target layout

```text
app/
  project.yml                 // XcodeGen spec, source of truth
  Gokan.xcodeproj             // generated; gitignored OR checked in (see below)
  Shared/
    GokanAppEntry.swift       // @main, picks platform-specific scene
    Info-iOS.plist
    Info-macOS.plist
    Gokan.entitlements        // macOS dev entitlements (App Sandbox off for now)
    Assets.xcassets/          // app icon, accent color
  iOS/
    SceneDelegate-ish glue if needed
  macOS/
    Commands, menu hooks
Package.swift                 // unchanged; still owns GokanCore/Engine/UI
```

Both app targets depend on the local SwiftPM package via Xcode's
"Add Local Package" (XcodeGen `packages:` stanza pointing at
`../Package.swift`) and link the `GokanUI` product. The existing
`GokanMacApp` SwiftPM executable target is removed once the macOS bundle
target builds, so we have one source of truth per platform.

Decision to make in the implementation PR: check in the generated
`Gokan.xcodeproj` or gitignore it. Recommended: **gitignore it** and add
a `make project` / `scripts/generate-xcodeproj.sh` wrapper so CI and
contributors regenerate from `project.yml`. This keeps diffs clean.

## Bundle Identifiers

Per `docs/naming.md`, the product name is `Gokan` and module/bundle
names use that spelling. Proposed scheme, mirroring common Apple
conventions:

- Organization identifier: `com.gokan` (placeholder; revisit before any
  TestFlight or App Store push — we may need a domain we actually own,
  e.g. `dev.richstyles.gokan` or whatever the eventual project domain
  resolves to).
- macOS app bundle ID: `com.gokan.Gokan`
- iOS app bundle ID:   `com.gokan.Gokan` (same ID across platforms is
  fine and simplifies iCloud / Universal Purchase later).
- Test bundle IDs: `com.gokan.Gokan.tests` (suffix per target).

Record the chosen organization identifier in `app/project.yml` under
`options.bundleIdPrefix` so every target inherits it.

## Signing Assumptions

For Milestone 3 we only need the bundles to build and run locally —
distribution and notarization come later.

- **macOS**: "Sign to Run Locally" (`CODE_SIGN_IDENTITY = -`) with
  automatic signing disabled. No paid Developer Program account
  required. App Sandbox stays **off** until we know what KataGo's
  process model needs; document this in `Gokan.entitlements`.
- **iOS Simulator**: no signing required; `CODE_SIGNING_ALLOWED = NO`
  for Simulator destinations.
- **iOS device**: automatic signing with a personal team; contributors
  set `DEVELOPMENT_TEAM` via a gitignored `app/Local.xcconfig` so the
  team ID never lands in git. `project.yml` references the xcconfig but
  ships it empty.
- Provisioning profiles, App Store Connect setup, and notarization are
  explicitly deferred. A follow-up milestone will introduce a paid
  team ID, a real bundle prefix, and `xcodebuild -exportArchive` flow.

## Verification Commands

All commands assume a clean checkout on Apple Silicon with Xcode 16+
installed.

```sh
# 1. Regenerate the Xcode project from the spec.
brew install xcodegen   # one-time
(cd app && xcodegen generate)

# 2. SwiftPM libraries still build and test on their own.
swift build
swift test

# 3. macOS app bundle builds and produces Gokan.app.
xcodebuild \
  -project app/Gokan.xcodeproj \
  -scheme Gokan-macOS \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug \
  build

# Locate the built bundle and sanity-check its Info.plist.
BUILT=$(xcodebuild -project app/Gokan.xcodeproj -scheme Gokan-macOS \
  -showBuildSettings -configuration Debug \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
ls "$BUILT/Gokan.app"
defaults read "$BUILT/Gokan.app/Contents/Info" CFBundleIdentifier
codesign -dv --verbose=2 "$BUILT/Gokan.app" 2>&1 | head -n 5

# 4. iOS Simulator build (no signing required).
xcodebuild \
  -project app/Gokan.xcodeproj \
  -scheme Gokan-iOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build

# 5. Boot the iOS app on a simulator end-to-end.
xcrun simctl boot 'iPhone 15' || true
xcodebuild \
  -project app/Gokan.xcodeproj \
  -scheme Gokan-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test    # runs the smoke UI test from Milestone 2

# 6. macOS unit/UI tests via xcodebuild (parity with `swift test`).
xcodebuild \
  -project app/Gokan.xcodeproj \
  -scheme Gokan-macOS \
  -destination 'platform=macOS,arch=arm64' \
  test
```

A green run of steps 2–6 is the done-criterion for Milestone 3.

## Risks and Follow-ups

- **Checked-in vs generated project.** Gitignoring `Gokan.xcodeproj`
  requires contributors to run `xcodegen` before opening Xcode. Mitigate
  with a `scripts/bootstrap.sh` and a README pointer.
- **Bundle ID placeholder.** `com.gokan` is not a domain we control.
  Resolve before any TestFlight, App Store, or signed distribution work
  to avoid renaming bundle IDs post-launch (painful for iCloud / data
  containers).
- **Sandbox + KataGo.** Enabling App Sandbox later will interact with
  KataGo's process model and any embedded engine path. Track in the
  KataGo roadmap, not here.
- **CI signing.** Milestone 3 keeps CI on "build only, no sign" for
  both platforms. A later milestone introduces a CI-signed macOS build
  and TestFlight pipeline once we have a paid team and real bundle
  prefix.
