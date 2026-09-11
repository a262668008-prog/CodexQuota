# Source scope and attribution review

## Included

- `native/main.m`: copied from the existing personal CodexQuota AppKit implementation and adapted for this source distribution.
- `scripts/build-app.sh`: adapted from the personal build script; output paths are now project-local.
- `scripts/check.sh` and documentation: prepared for this distribution with Codex assistance.

The user identifies the tool as their own project and has agreed in principle to making its code public. The local main source contains no third-party copyright or license header. This does not independently prove the provenance of every line; author review remains necessary before publication.

## Excluded

- Iron Man / Spider-Man character skin PNGs: no redistribution permission was found in the inspected project; replaced with plain native color themes.
- Original icon assets: provenance was not established in this inspection; no custom icon is bundled.
- Generated `protocol-schema` and `protocol-ts` reference folders: not needed to build; excluded rather than assigning them this project's MIT license.
- Superseded Swift implementation, its tests, design studies, build artifacts and personal installation script: not part of the current AppKit distribution.
- All preferences, account history, credentials, session logs and private vault notes.

## Dependencies

Apple Cocoa and QuartzCore system frameworks are linked, not redistributed. Codex is a separately installed prerequisite and is not bundled. The source sends JSON messages to its app-server; protocol compatibility may change.

MIT is the proposed license for this local review copy. Publication has not occurred. OpenAI and Apple names refer to their respective products; no affiliation is claimed.
