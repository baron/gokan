# Compliance Notes

This is planning material, not legal advice.

## KataGo

KataGo's repository license is MIT-style for the main code, with separate
notices for vendored dependencies. The official KataGo network files on
katagotraining.org are also MIT-style. That means a GPL app can usually include
or depend on KataGo code and models, provided all required notices are preserved.

Practical requirements:

- Keep KataGo copyright and license notices.
- Keep vendored dependency notices from `cpp/external`.
- Track model license text with downloaded/bundled networks.
- Do not imply upstream endorsement of the fork or app.
- Prefer keeping the KataGo fork permissively licensed if upstreaming patches is
  a goal.

## GPL App License

Gokan's original app code is licensed as GPL-3.0-or-later:

- GPL-3.0-or-later for the app code.
- MIT preserved for KataGo-derived files unless there is a deliberate reason to
  relicense local changes.
- Clear `LICENSE_POLICY.md` and `THIRD_PARTY_NOTICES.md` files.
- Complete corresponding source for every distributed binary.

The root GPL license does not remove or replace the upstream licenses of
KataGo-derived files, vendored dependencies, or neural network files.

## Apple Distribution Caveat

Publishing a pure GPL app through Apple's App Store can be legally awkward
because Apple distribution terms and DRM/usage restrictions may add constraints
that GPL licenses do not permit. Options to evaluate before release:

- distribute macOS builds outside the Mac App Store with notarization;
- use TestFlight/App Store only if counsel approves the GPL posture;
- add an explicit App Store exception if all copyright holders agree;
- choose a permissive/MPL-style app license instead of GPL for App Store builds.

## Build Reproducibility

For credibility as an open project:

- document exact Xcode, CMake, Ninja, and Swift versions;
- script engine builds;
- publish checksums for bundled model files;
- publish benchmark devices and configs;
- avoid checking large neural network binaries into git.
