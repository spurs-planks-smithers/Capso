# Feedback activation for Nextshot 0.5.0

This handoff prepares native feedback submission for 0.5.0. It does not build or publish a production app. Website feedback is available separately at https://feedback.nextshot.dev/.

The existing 0.4.0 release is immutable. Do not replace its files or tag. The normal release command must advance VERSION from 0.4.x to 0.5.0.

## Freeze the release graph

Merge this handoff and every intended parallel pull request first. The website task leaves native admission off. Enable it as an explicit release-owner action with `python3 site/feedback/deploy.py native`. Submit a synthetic reduced package through the real app transport. Confirm that receipt completes screening and its notification send. If the check fails, run `python3 site/feedback/deploy.py web` and stop the app activation. Complete the signed Dev app review described in [[feedback-intake]]. Leave all other flags unchanged.

Reserve main for one activation commit followed by the normal release commit. Stop all parallel merges and commits until the release completes. The helper does not lock Git or contact GitHub. Coordinate this freeze with other writers.

Use a clean checkout on main with no other session writing there. Fetch origin and its tags. Do not reset or discard another session's work.

```sh
git fetch origin --tags
git switch main
git pull --ff-only origin main
python3 scripts/prepare-feedback-release.py --plan
python3 scripts/prepare-feedback-release.py --apply
git diff -- Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift
```

The helper requires main, a clean tree, HEAD equal to origin/main, VERSION 0.4.x, and no local nextshot-v0.5.0 tag. It requires exactly one expected supportSubmission spec. Fetching tags makes the local tag check current.

Apply changes only that flag's two defaults to on and sets releasedInBuild to the current commit count plus two. Those two commits are the activation commit and the normal release commit. The marker remains the first released build, not the first source build. The helper never commits, changes VERSION, edits release notes, builds, or publishes.

## Review and check the activation

Review the diff. It must contain only the supportSubmission defaults and marker. Existing tests must pass before the activation commit.

```sh
swift test --package-path Packages/FeedbackKit
swift test --package-path Packages/SupportKit
xcodegen generate
xcodebuild test -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:CapsoTests
```

These commands check existing native behavior. They do not create a signed production release. Check the submission panel, explicit Submit action, and receipt in the reviewed Dev app. Confirm the changelog's Unreleased notes describe the activation before the graph freeze. Do not add a release-note commit after apply.

Commit only the activation file. Check the full GitHub route before pushing.

```sh
git diff --stat -- Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift
git add Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift
git commit -m "feat: enable reviewed support submission for 0.5.0" -- Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift
github-route status
git push origin main
```

Stop if routing fails. Wait for the existing hosted checks on the exact activation commit. Do not add a commit to rerun checks. A later merge or commit invalidates the marker. Stop and recalculate through a reviewed activation change if the graph changes.

## Owner performs the release

After the activation push and passing checks, fetch again and verify the frozen graph.

```sh
git fetch origin --tags
python3 scripts/prepare-feedback-release.py --verify
```

Verify requires clean main at origin/main, VERSION 0.4.x, no 0.5.0 tag, and enabled defaults. The marker must equal HEAD's commit count plus one. A changed count fails verification. Keep the freeze through the normal release command's commit.

Drew runs the following command in a terminal after verification. This handoff does not run it.

```sh
scripts/release.sh 0.5.0
```

The normal command performs required checks, creates the release commit, builds and notarizes, and asks for publication approval. Its release build count must equal the flag marker. Confirm that value in the release plan and app metadata before publication. The website guide labels native submission as coming in 0.5.0 until that release is live.
