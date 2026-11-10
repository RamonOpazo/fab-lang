# Releases

Decision note, 10 November. How a build of fAB names itself, how versions advance, and how commits are written so a changelog can be made from them. It concerns every package alike: fab-core, fab-render, fab-lsp and fab-cli share one version.

## 1. Two kinds of build

A build is **stable** or **dev**, and the source tree it is built from decides which, never a flag.

| Kind | When | Version | Example |
| --- | --- | --- | --- |
| stable | the commit is tagged `vX.Y.Z`, and the working tree is clean | `X.Y.Z` | `0.1.0` |
| dev | any other commit | `X.Y.Z-dev.N+HASH` | `0.1.0-dev.96+4b0aaa8` |
| dev, changed | the working tree differs from its commit | `X.Y.Z-dev.N+HASH.dirty` | `0.1.0-dev.96+4b0aaa8.dirty` |

- **`X.Y.Z` is the version being worked towards,** written once in the source: until a release, the next one. A dev build of `0.1.0` comes before `0.1.0`.
- **`dev.N` counts the commits since the last tag,** or since the first commit while there is none, so dev builds order themselves: `dev.96` before `dev.97`.
- **`+HASH` is the commit,** abbreviated as `git` abbreviates it. It is build metadata: it says which build, and plays no part in ordering.
- **`.dirty`** is a working tree with uncommitted changes. A tagged commit built dirty is a dev build.
- **Without git** (a source archive), a build cannot know its commit: it is `X.Y.Z-dev+unknown`, never stable.

The scheme is Zig's own (`0.14.0-dev.3445+6c3cbb0c8`), which is semantic versioning's: the pre-release (`-dev.N`) orders, the build metadata (`+…`) identifies.

**Rejected.** Release candidates and nightly builds: nothing is published yet, so neither has anyone to serve; either can be added as a form of its own later (`-rc.N`, a dev build published on a schedule). A `-Ddev` build option: the kind of build would be a choice anyone could make, and a stable-looking build could admit unsupported constructs; the tree already knows whether it is a release.

## 2. Incomplete builds

**Only a dev build may admit unsupported constructs** (amends `statements.md` §15, *unsupported never ships*). A stable build refuses to compile while any unsupported tag remains, in any optimisation mode; a dev build compiles in any mode, optimised included, so the editor can run a fast build while the plan is unfinished (`profile.md`, G4).

**A dev build that admits any is marked `incomplete`,** in its build metadata: `0.1.0-dev.96+4b0aaa8.incomplete`, after `.dirty` when both hold. It is a fact about the compiler, known when it is compiled (some tag of `Error.Tag` has the unsupported severity), not about a program: a program using an unsupported construct says so in its diagnostics. Its version is shown wherever a build names itself:

- `fab --version`: `fab 0.1.0-dev.96+4b0aaa8.incomplete`;
- the language server's `serverInfo.version`, so editors show it;
- the JSON output, a top-level `"version"`, beside the format's;
- generated files, as a comment naming their generator (`// fab 0.1.0-dev.96+4b0aaa8.incomplete` in DOT), so a drawing tells what made it.

The optimisation mode is not part of the version, as in Zig.

## 3. One version, written once

The version worked towards is written once, and the build makes the rest: it asks git for the last tag, the count since it, the commit and whether the tree is clean, and gives the result to the code as a compile-time constant. Every place that shows a version reads that constant: today `0.0.0` is written seven times (four `build.zig.zon`, `fab-cli/src/main.zig`, `fab-lsp/src/Server.zig` and the server's `serverInfo`).

A tagged build checks that its tag and the written version agree, and refuses to build if they don't.

**The JSON format's own version is 1, and stays 1 while the language is being formalised,** whatever changes in the format meanwhile: its consumers follow the compiler's version until then. Counting format versions starts once the language is formalised. (It had reached 2 with the Sheet, `statements.md` §22.13, and 3 with `@` removed, §23.1, before this was settled.)

**Zig's own tooling does it.** fab-core's `build.zig.zon` holds the version written (`.version = "0.1.0"`). fab-core's `build.zig` reads it (`@import("build.zig.zon").version`), runs `git describe` (`b.runAllowFail`), as Zig's own build does, and hands the full version to the code through build options (`b.addOptions()`), with whether the build is incomplete; fab-core exports both, `fab.version`. fab-render, fab-lsp and fab-cli read them from fab-core, which they depend on already. Zig requires a version in every manifest, so the other three hold the same literal, and a check in `make test` fails when any differs.

As elsewhere: Cargo hands `Cargo.toml`'s version to the code (`CARGO_PKG_VERSION`), and Python reads `pyproject.toml`'s from the installed package's metadata, or derives it from git tags (`setuptools-scm`), as `git describe` does here.

## 4. Versions advance

**Before 1.0.0, minor versions may break.** fAB is pre-alpha (CLAUDE.md): until 1.0.0 the language, the CLI and the JSON format change without notice. Below 1.0.0, a change that breaks what worked raises the minor version (`0.1.0` to `0.2.0`), and anything else the patch (`0.1.0` to `0.1.1`), as Cargo reads semantic versioning below 1.0.

**1.0.0 is stable and complete enough to rely on:** the language as the spec states it, fAB's own renderer (step 10) drawing it, and the JSON format fixed. From then on, semantic versioning as written: major for what breaks, minor for what is added, patch for fixes.

**A release** is one commit: the version written, the changelog written, the commit tagged `vX.Y.Z`. The next commit writes the version worked towards after it, so every dev build after a release names the release it leads to. **The first release is 0.1.0.**

**0.1.0 is feature completeness:** fAB is worked on as `0.1.0-dev` until the plan is complete, and 0.1.0 is its first release with an artifact, on GitHub. The release's procedure (how the version is written and tagged, what is checked, the artifact) is settled then.

## 5. Commits and the changelog

**Commits follow Conventional Commits,** as the history already does: `type(scope): subject`, with an optional body and footers.

- **Types:** `feat` (a capability), `fix` (a defect), `perf` (speed or memory, behaviour unchanged), `refactor` (structure, behaviour unchanged), `docs` (the spec, the notes, the README), `test`, `build` (the build, the Makefile, versions), `style` (formatting only), `chore` (anything else).
- **Scopes:** a package (`fab-core`, `fab-render`, `fab-lsp`, `fab-cli`, `tree-sitter-fab`), `spec`, `examples`, `editors`; none when a commit spans several.
- **Subjects** say what the change does, in the project's prose, ending with the plan step when there is one: `feat(fab-core): base rules, shared by every diagram (step 9d5d).`
- **Breaking changes** are marked `!` after the scope (`feat(fab-core)!: …`) and explained in a `BREAKING CHANGE:` footer. Before 1.0.0 most changes may break; the mark is for what a user of the CLI, the JSON or the language would notice.

**The changelog starts after 0.1.0.** From then on it is made from the commits since the last tag, at each release, into `CHANGELOG.md`: the breaking changes first, then features, fixes and performance, each under its scope; `refactor`, `test`, `style` and `chore` left out. It is generated, then read and edited by hand in the release commit.

What generates it is settled with the first release after 0.1.0. Fewer dependencies are better: `git log` read with Zig's own tooling, rather than a changelog tool from another toolchain.
