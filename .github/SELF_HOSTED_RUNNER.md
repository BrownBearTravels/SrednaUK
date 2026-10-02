# Self-hosted runner (M4 Mac mini)

The Mac mini is the single self-hosted GitHub Actions runner for this repo. It runs
the workloads GitHub-hosted Linux can't do cheaply: **iOS CI**, **QA on a real
emulator/Simulator**, and the **Android build** (fast on Apple silicon).

| Workflow | Trigger | What runs on the mini |
|----------|---------|-----------------------|
| `ios-ci.yml` | push to `main` (`ios/**`) | `swiftlint --strict`, `swift test`, Simulator `xcodebuild` |
| `android-build.yml` | push to `main` (app code) | core + app unit tests, `assembleDebug`, lint |
| `qa.yml` (`smoke`) | push to `main` (`android/**`,`ios/**`,`qa/**`) | Android smoke suite on the emulator |
| `qa.yml` (`nightly`) | 01:00 Europe/Sofia (cron `7 19 * * *` UTC arrives early; the hosted `wait-for-1am` job holds it until 01:00) + manual | Android **and** iOS full suites, in parallel |

## Security model — why push-to-`main` only

The repo is **public**. A self-hosted runner that ran `pull_request` events would let
anyone execute arbitrary code on this machine by opening a fork PR. Every self-hosted
workflow here therefore triggers on **push to `main`** (plus `schedule`/`workflow_dispatch`)
and **never on `pull_request`**. Pushing to `main` is maintainer-only, so there is no
fork-PR exposure and no `if`-guard gymnastics are needed.

**Do not add `pull_request:` triggers to these workflows.** Fork-PR validation, if ever
wanted, must stay on GitHub-hosted `ubuntu-latest`.

## Runner registration

- The runner (`mmm4`) is registered at the **organization** level, not the repo level.
  GitHub blocks/discourages repo-level self-hosted runners on **public** repos (fork-PR
  risk), so org-level is the correct and supported setup. Jobs match by label, so scope
  doesn't matter as long as this repo is granted access (below).
- It carries the custom label **`srednabg`** (alongside the default `self-hosted`,
  `macOS`, `ARM64`). All jobs target `runs-on: [self-hosted, macOS, srednabg]`, so other
  org runners won't accidentally pick up these jobs.
- **Org runner group must allow this public repo.** In *Org → Settings → Actions →
  Runner groups → <group>*: enable **"Allow public repositories"** (off by default) and
  ensure `SrednaBG` is in the group's **Repository access**. Also check *Org → Settings →
  Actions → General* doesn't have a policy disallowing self-hosted runners on public
  repos. Without this, pushes to `main` will queue forever with no runner.
- **Run the runner inside the logged-in desktop session, NOT as a headless
  `LaunchDaemon`.** The iOS Simulator requires an active GUI session for Metal
  rendering (`qa/CLAUDE.md`: "Headless on a Mac mini: the iOS Simulator needs an active
  GUI session. No workaround."). Install it as a per-user `LaunchAgent` (the runner's
  `./svc.sh install` under a logged-in user, with auto-login enabled on the mini) so
  Simulator-driven QA works. The Android emulator and the build/lint jobs work in either
  mode, but iOS QA does not.

## Toolchain prerequisites (must be on the runner's `PATH`)

The workflows assume these are installed and reachable in the runner's environment:

- **Xcode 16+** + Command Line Tools, signed in, with an **iOS Simulator runtime**
  installed (`xcrun simctl list runtimes` shows an iOS entry). `xcodebuild`, `xcrun`,
  `swift`.
- **SwiftLint** (`swiftlint` on `PATH`; `brew install swiftlint`).
- **JDK 17** — `actions/setup-java@v5` provisions it per-run, so a system JDK is
  optional. `unzip`/`curl` are stock on macOS.
- **Android SDK** with `ANDROID_HOME`/`ANDROID_SDK_ROOT` set and **`adb` + `emulator`
  on `PATH`**, plus a **`Pixel_8a` AVD** (override with `SREDNABG_AVD`).
- **Python 3** — `scripts/setup-python.sh` provisions the repo `.venv`; the `qa/*.py`
  entrypoints auto-use it.

> The runner's `LaunchAgent` env does **not** match an interactive shell, so the SDK
> and Xcode toolchain aren't on its `PATH`. The workflows handle this themselves via
> `.github/scripts/setup-env.sh`, which resolves `ANDROID_HOME`, adds `adb`/`emulator`
> to the path, and points `DEVELOPER_DIR` at full Xcode (the CommandLineTools toolchain
> lacks `sourcekitdInProc`, which is what made SwiftLint crash). You just need Xcode +
> the SDK + `swiftlint` actually installed on the machine. If SwiftLint still fails to
> load sourcekit, run once on the runner: `sudo xcode-select -s /Applications/Xcode.app`.

## Signing credentials — not required

Nothing here needs signing secrets: iOS builds target the Simulator with
`CODE_SIGNING_ALLOWED=NO`, the Android build is debug (auto debug-keystore), and QA
installs the debug APK. **Android release signing stays on GitHub-hosted**
`android-release.yml` with its existing keystore secrets. If release automation ever
moves to the mini, see the credential-transfer appendix in the implementation plan.

## Helper scripts

`qa.yml` and `android-build.yml` call small scripts under `.github/scripts/`:

- `download-map-bundle.sh` — fetch + unzip the offline map bundle (shared with the
  Android build; the app's `validateMapBundle` task needs it present).
- `boot-emulator.sh` — boot the `Pixel_8a` AVD headless and wait for `sys.boot_completed`.
- `android-build-install.sh` — `assembleGmsDebug` + `adb install -r` (QA uses the gms
  flavor on the emulator).
- `ios-build-install.sh` — build the Debug `.app`, boot a Simulator, `simctl install`.

## Single-runner notes

One runner executes one job at a time. The QA jobs share a `concurrency: { group: qa }`
so they never overlap, and `nightly` runs Android + iOS **concurrently inside one job**
(background processes, separate `--reports-dir` trees) rather than as a matrix (which
would serialise on a single runner). If short build/lint jobs start queueing behind a
long nightly, register a second runner service for the build jobs and keep
emulator/Simulator QA on this one.

## Nightly start time — and a future option

The nightly starts at **01:00 Europe/Sofia**. GitHub's cron can't do that by itself
(best-effort — the old `0 1 * * *` arrived 1–6 h late — and UTC-only), so `qa.yml`
fires its cron early (`7 19 * * *` UTC) and a GitHub-hosted `wait-for-1am` job sleeps
until 01:00 local before the nightly job is released to this runner. Manual
`workflow_dispatch` runs skip the wait.

That costs a hosted runner up to ~4 h of sleeping per night (free on a public repo)
and still depends on GitHub delivering the cron before 01:00.

**Future option — trigger from the runner itself (not set up).** The mini currently
holds **no `gh` CLI and no GitHub credential, on purpose**: the runner doesn't need
one. If `gh` ever gets installed and logged in here for other work, the nightly can
drop the cron + wait job and be started locally instead, which is exact, DST-proof and
independent of GitHub's scheduler:

- a LaunchAgent in `~/Library/LaunchAgents` (same GUI session as the runner) with
  `StartCalendarInterval` `Hour=1 Minute=0`;
- `ProgramArguments`: `/opt/homebrew/bin/gh workflow run qa.yml --repo demosten-com/SrednaBG --ref main`
  — a `workflow_dispatch`, whose defaults are already `suite=nightly`, `platforms=both`;
- the login needs the `workflow` scope and write access to the repo;
- load with `launchctl bootstrap gui/$(id -u) <plist>`, test with `launchctl kickstart`.
  A missed 01:00 (machine asleep) fires once on wake.

When switching, remove `schedule:` and the `wait-for-1am` job from `qa.yml` in the same
change — otherwise every night runs twice. Don't add the credential *for* this; it is
only worth doing if `gh` is on the box anyway.
