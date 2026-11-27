# Token Codex Info — Development notes

Menu bar utility for showing Codex usage limits on macOS.

Requires macOS 14 Sonoma or later. Release builds support both Apple Silicon
and Intel Macs. Building from source requires Xcode 15 or later (Swift 5.9+).

## Install

Download the universal `.dmg` from this repository's **Releases** page, open it,
and drag **Token Codex Info.app** into **Applications**. Launch it from there;
the usage indicator appears in the menu bar, without a Dock icon.

The current build uses an ad-hoc signature and is not notarized by Apple.
macOS may require you to allow it in **System Settings → Privacy & Security →
Open Anyway** after the first launch attempt. Only do this for a build you trust.

Use Codex on the same Mac so it can write local usage snapshots. The app reads
local Codex session files and databases; it does not make network requests or
require an API key. Usage can lag behind the account until Codex writes a new
snapshot. Token-based fallbacks are estimates.

## What It Shows

- The menu bar item shows the best available Codex usage window: remaining percent and reset time/date.
- If the 5-hour Codex limit is available, it is shown as a countdown.
- If Codex only reports the weekly limit, the app falls back to weekly remaining percent and reset date.
- Left-click the menu bar item to see the data source and open Data & Settings, Launch at Login, Refresh, and Quit.

The left-click menu intentionally does not duplicate usage rows because the same usage information is already visible in the menu bar item. The menu opens slightly below the status item so it does not overlap the menu bar title.

Examples:

```text
83% · 2:14
100% · 10 Aug
```

## Data Sources

The app reads the most accurate Codex data first:

1. `~/.codex/sessions/**/*.jsonl` `payload.rate_limits` events, with fallback support for older top-level `rate_limits` events.
2. `~/.codex/logs_2.sqlite` `codex.rate_limits` events.
3. `post sampling token usage` log estimates.
4. `~/.codex/state_5.sqlite` thread token estimates if logs are unavailable.

Session JSONL is preferred because recent Codex usage snapshots are written there with `used_percent` and `resets_at` fields. The parser reads `payload.rate_limits` first, then falls back to the older top-level `rate_limits` object so both current and historical Codex session formats work. SQLite rate-limit matching is intentionally strict so command output, patches, or test fixtures in logs are not mistaken for real Codex events.

Codex rate-limit snapshots are classified by `window_minutes`, not by the field names `primary` and `secondary`. This matters because newer Codex sessions may report only one window, for example `primary.window_minutes = 10080` with `secondary = null`. In that weekly-only case, the app does not fabricate a missing 5-hour row or show a misleading `100% / --`; it displays the weekly snapshot instead.

If one session JSONL file cannot be read while Codex is writing it, the provider skips that file and continues looking for the next valid snapshot instead of falling back to empty or estimated data.

Expired rate-limit windows are not treated as unused. A valid weekly window is used when available; otherwise the provider tries token estimates and then reports that no usage data is available. It never invents a new reset time or a full allowance from an expired snapshot.

Token estimates also require activity within the selected window. If local activity
exists only in the weekly window, the app shows that weekly estimate and its date,
instead of fabricating a full five-hour allowance with an unknown reset.

The first read runs in the background. While it is in progress, the menu shows `Codex · Checking`. The first-launch window reports folder access, allows folder selection, and can be reopened from Data & Settings. Changing settings discards any in-flight result for the previous configuration.

SQLite reads are executed through `/usr/bin/sqlite3` with a timeout and temporary output files. This avoids pipe deadlocks on large log queries and keeps the manual Refresh action from getting stuck in `Refreshing...`.

Temporary query output and errors are created with owner-only permissions (`0600`)
and removed after the query completes.

## Display Notes

- Codex reports `used_percent`; the app displays remaining percent.
- For example, `used_percent: 42` becomes `58%`.
- If a reset time is unavailable, the menu bar shows `--` instead of `0:00` so an unknown reset is not confused with an expired countdown.
- Manual Refresh is available from the left-click controls menu. While refresh is running, the item is disabled and shown as `Refreshing...`.
- The menu bar countdown is rendered as a single static title so macOS can apply the correct active and inactive menu bar text colors.
- The controls menu forces the Aqua appearance so dropdowns stay light even when an external display reports a dark effective appearance.
- Percentages can change quickly while Codex is active. Reset times such as `5:52 PM` and `11 Jul` may stay the same while remaining percentages move.

## Run

Use the project run script:

```sh
bash ./script/build_and_run.sh
```

That script stops the existing `TokenCodexInfo` process, builds the Swift package, stages a fresh `Token Codex Info.app` bundle under `dist/`, and launches it.

Useful variants:

```sh
bash ./script/build_and_run.sh --verify
bash ./script/build_and_run.sh --logs
```

## Test

```sh
swift test
```

## Build a Release

```sh
bash ./script/package_dmg.sh
```

This builds a universal release binary, verifies both CPU architectures,
packages and ad-hoc signs `dist/Token Codex Info.app`, and produces:

- `dist/TokenCodexInfo-1.0.0-universal.dmg`
- `dist/TokenCodexInfo-1.0.0-universal.zip`
- `dist/SHA256SUMS.txt`

Set `VERSION` and `BUILD_NUMBER` for a different release:

```sh
VERSION=1.0.1 BUILD_NUMBER=2 bash ./script/package_dmg.sh
```

## GitHub Builds and Releases

GitHub Actions runs tests and builds downloadable DMG and ZIP artifacts on
pushes to `main`, pull requests, and manual workflow runs. Download them from
the successful run's **Artifacts** section.

To prepare a release after publishing the repository:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The tag workflow tests and packages the app, then creates a **draft** GitHub
Release with the DMG, ZIP, and checksums attached. Review the draft and publish
it when ready. Tag versions must use `vX.Y.Z`.
