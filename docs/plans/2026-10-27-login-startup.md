# Quiet login startup implementation

**Spec:** [Issue 154](https://github.com/spurs-planks-smithers/Capso/issues/154), approved October 27, 2026. Drew confirms that disabling the app in macOS must survive updates.

**Goal:** Default a fresh installation to quiet login startup while preserving every later user choice.

**Architecture:** StartupKit records one-time consent and setup completion. App/Feedback adapts macOS service status, installed-app checks, and Settings controls. Routine launch never restores an enabled preference.

## Constraints

- Registration requires explicit installer or Settings consent.
- Installer consent is a one-use token. Consume it before any registration attempt.
- A completed setup key has no version suffix. Updates do not reset it.
- Existing or unknown legacy use retains the system state.
- Dev requires an explicit Settings action. Release enrollment requires a verified installed signature.
- Login launch skips activation, updater startup, recording recovery, permission queries, restored-round help, optional key warm-up, and pending file/URL actions.
- The installed Dev build remains under the catalog settings chat's hold. Do not replace or control it.
- Add no repository tests or gates. Use existing suites and a temporary policy probe.

## Work

- [x] Add the Foundation-only enrollment policy and native service adapter.
- [x] Add a fresh-install checkbox and a one-use handoff after successful installation.
- [x] Replace the Settings switch with the system-backed control and compact first-use confirmation.
- [x] Apply quiet login guards and retain explicit reopen behavior.
- [x] Review Guides for released-version accuracy. Record new behavior under Unreleased.
- [x] Run existing package/app checks and review the diff.

## Review focus

- Disabled macOS status, a saved on choice, and an update must produce zero register calls.
- A failed registration cannot schedule an automatic retry.
- Missing or replayed installer tokens cannot register the app.
- DMG, helper, test, and transient copies cannot enroll.
- Native login, approval, and first-use layout acceptance remain pending while review control is held.

## Validation

- StartupKit and the complete unsigned app build pass.
- The temporary policy probe passes 72 checks. It uses isolated preferences and intercepts the system service.
- The existing app suite passes all 247 tests. FeedbackKit passes 341 tests. The existing network scan passes three checks, and all 22 site tests pass. No repository test is added.
- Guides retain their released 0.4.0 review version. The default row names that release explicitly. New install controls remain under Unreleased until signed review and release.
- Native sign-in, system approval, and first-use layout checks remain pending. The held installed Dev build is unchanged.

The final review also checks restored active rounds. Login suppresses their help overlay and optional key warm-up until a user begins another capture.
