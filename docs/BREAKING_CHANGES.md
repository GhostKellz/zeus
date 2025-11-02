# Breaking Changes Policy

The Zeus Vulkan library follows semantic versioning to provide predictable evolution of its public API. This document explains how we classify releases and communicate any potentially disruptive change.

## Versioning Commitments

- **Semantic Versioning (SemVer)** – Releases are tagged as `MAJOR.MINOR.PATCH`.
  - Increment the **PATCH** number for bug fixes that do not alter the API surface or observable behaviour.
  - Increment the **MINOR** number for additive features that remain backward-compatible.
  - Increment the **MAJOR** number when a change requires user code modifications or drops previously supported behaviour.
- Each published package advertises the minimum supported Zig toolchain in `build.zig.zon` and in the release notes.

## Stability Guarantees

- Public symbols exported from `root.zig` and documented modules remain stable within a major release line. Changing function signatures, struct layouts, error sets, or required init options is considered a breaking change.
- Behavioural guarantees (e.g. telemetry units, frame pacing contracts, resource lifetime rules) are treated as part of the API. Alterations that would force downstream adjustments are scheduled for a major release.
- Internal modules may evolve between minors provided the public contract does not change. When in doubt, promote helpers to the public surface before depending on them externally.

## Deprecation Process

1. **Mark & Warn** – Introduce a replacement API and annotate the legacy entry point with documentation or compile-time warnings where practical.
2. **Grace Period** – Maintain the deprecated path for at least one MINOR release, giving downstream projects time to migrate. Provide migration notes in `docs/MIGRATION.md` when behaviour changes.
3. **Removal** – Remove the deprecated surface only in a subsequent MAJOR release.

## Communicating Breaking Changes

- Every release includes a `BREAKING CHANGES` section in the changelog or release notes that enumerates affected symbols, the rationale, and migration steps.
- TODO lists and project roadmap entries (`TODO.md`) are updated alongside implementation to reflect the new expectations.
- When a change requires environment adjustments (e.g. newer Vulkan extensions or kernel parameters), the requirement is documented in `README.md` and the performance/validation guides.

## Exception Handling

Rare situations (security patches, upstream Zig regressions) may require bending the grace-period rule. In those cases we:

- Publish an out-of-band advisory describing the urgency.
- Provide a compatibility shim or branch when feasible.
- Note the deviation prominently in the release notes.

By adhering to this policy we ensure integrators—like Grim and sibling projects—can update with confidence while still allowing Zeus to iterate quickly on high-performance rendering features.
