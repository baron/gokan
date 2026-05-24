# License Policy

Gokan's original application code is licensed under the GNU General Public
License, version 3 or later:

```text
SPDX-License-Identifier: GPL-3.0-or-later
```

The full GPLv3 text is in [LICENSE](LICENSE).

## Scope

Unless a file says otherwise, original source files written for Gokan are
licensed as GPL-3.0-or-later.

This project also integrates upstream open-source components that keep their
own licenses. In particular:

- `engine/KataGo/`, when fetched, is the upstream KataGo checkout or a fork of
  it. KataGo-derived files keep KataGo's upstream MIT-style license and notices.
- KataGo's vendored dependencies keep the notices found in KataGo's
  `cpp/external` tree.
- KataGo neural network files keep the license published with the model source.

Do not remove upstream copyright or license notices when importing, modifying,
or distributing KataGo-derived code.

## New Files

Use an SPDX header in new source files where the language supports comments:

```text
SPDX-License-Identifier: GPL-3.0-or-later
```

For files derived from KataGo, keep the upstream notice and use the license
identifier that matches that file instead of GPL-3.0-or-later.

## Distribution Checklist

Before distributing a binary build:

- include Gokan's GPL license text;
- include Gokan source code or a valid written/source offer as required by GPL;
- include KataGo's license and dependency notices;
- include license text and checksums for bundled neural network files;
- publish the exact KataGo commit used for the build;
- document local patches to KataGo, if any.
