# Changelog

## 2026-10-15

### Added

- Shared Haskell Step loader with source-file checks and a 20-second compilation timeout.
- Request context elision above 400,000 characters, preserving the latest 24 messages and full stored conversation history.
- Indexed recovery of original archived messages.
- Command execution helper with retained logs, bounded summaries, exit status, timeouts and process-group cleanup.
- Bash script helper with `errexit`, `nounset`, `pipefail` and failure-line reporting.
- Text, outcome and failure summaries with compiler diagnostics, GHC warning counts and missing-library detection.
- Source checks covering application modules, configuration and the Stack lock file.
- Helpers for Stack builds, Step compilation checks and comparisons between running and installed executables.
- Native shared-library preflight using `ldd`.

### Changed

- New user input supersedes older requests; execution checks the current request generation before dispatch.
- Cancelling a request before execution preserves worker memory and registered actions.
- Interrupted execution and execution transport failures reset the worker and record possible partial effects.
- Request failures are recorded in conversation history, with bounded error excerpts and full redacted error artifacts.
- Long command reports include recovery paths and prioritize terminal status and diagnostic context.
- Summary budgets account for metadata and preserve complete output when it fits.
- Cabal includes the root source directory, registers the runtime modules and declares `vector`.
- Docker packaging includes all five root helper modules.

### Fixed

- Stale request failures could pause newer user input.
- Source checks could lose the compiler exit status during the final source-snapshot comparison.
- Shell pipelines could hide earlier failures behind a successful final command.
- Shell error reporting could overwrite the caller's `status` variable.
- Report headers could crowd out summary content or cause recovery paths to be truncated.
- Fixed output reserves could compact logs that fit within the available budget.
