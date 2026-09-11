# CodexQuota

A small native macOS menu-bar and floating widget for viewing Codex usage limits.

[中文说明](README.zh-CN.md) · [Privacy](PRIVACY.md) · [Source review](SOURCE-REVIEW.md)

Independent community project; not an OpenAI product. Initial open-source preparation based on Jason's personally used 0.3.2 app. No public adoption or download claims are made.

## Features

- Current account's available short-window and weekly usage limits, reset countdowns, and credits.
- Compact progress bars expand into a floating panel; draggable, lockable, and hideable.
- Three plain color themes in this source distribution.
- Local account history: previous accounts show historical snapshots, not live balances.
- Recent project Token proportions computed locally from Codex session logs. These are estimates from recorded usage, not billing or subscription-quota allocation.
- Automatic refresh every 60 seconds and manual refresh.

## Requirements and build

macOS 14 or later, Apple Command Line Tools (`xcode-select --install` if missing), and an installed Codex executable with a signed-in ChatGPT account. UI text is currently Chinese. No Python, Node packages, or full Xcode required to build.

```sh
zsh scripts/build-app.sh
open build/CodexQuota.app
```

The build replaces only its generated `build/CodexQuota.app`. It does not install, launch, or replace an existing desktop app. For an optional manual installation, quit the previous instance and copy the built app to a location you choose in Finder. This build uses a separate preferences identifier from Jason's original app.

Codex executable locations checked: `/Applications/ChatGPT.app/Contents/Resources/codex`, `/Applications/Codex.app/Contents/Resources/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`. Other installation locations and custom Codex home directories are not currently supported. Sign in through Codex itself; this widget does not switch accounts.

The application is locally ad-hoc signed, not notarized. macOS may ask for confirmation before first opening. Only open builds whose source you trust. No prebuilt release or automatic updater is provided.

## Verification

```sh
zsh scripts/check.sh
```

Builds and checks the bundle, then runs the existing incremental-log-parser self-test with synthetic data. The check requires a macOS graphical session. It does not query live account balances. Live compatibility depends on the installed Codex app-server protocol and should be checked after upgrades.

## Contributing

Describe your macOS version, Codex version, expected result and actual result. Remove account identifiers, local paths and conversation text from bug reports. Small focused changes are welcome. Never attach `auth.json`, tokens, or complete session logs.

## License

MIT for the code and documentation in this source distribution; see LICENSE and SOURCE-REVIEW.md. Original character artwork, private settings, generated protocol reference trees and the superseded Swift implementation are excluded.
