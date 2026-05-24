# Third-Party Notices

This file tracks third-party components that Gokan expects to use. It should be
updated whenever a dependency is added, bundled, or removed.

## KataGo

- Project: KataGo
- Upstream: https://github.com/lightvector/KataGo
- License: MIT-style license with additional dependency notices
- Local path: `engine/KataGo/` after running `scripts/fetch-katago.sh`

KataGo source files and KataGo-derived fork changes must preserve upstream
copyright and license notices. KataGo's bundled third-party dependencies are
tracked inside its `cpp/external` directory and may use their own licenses.

## KataGo Neural Networks

- Source: https://katagotraining.org/networks/
- License page: https://katagotraining.org/network_license/
- Local path: `models/` for downloaded/cached files

Neural network binaries should not be committed to this repository. If a release
bundles a model, include the model filename, source URL, checksum, and license
text in the release materials.

## Apple SDKs

Gokan is intended to build against public Apple SDKs provided by Xcode. Apple
SDKs are not redistributed by this repository.
