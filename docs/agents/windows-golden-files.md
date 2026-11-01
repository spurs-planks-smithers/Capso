# Windows golden files

The folders in `Windows/golden/` hold the text that the Mac app writes for a round. The Windows app must write the same bytes. The test `GoldenParityTests` checks this.

## What the test compares

For each golden folder, the test loads `feedback.json`. It writes the round through `RoundStore` with the real `BundleTextRenderer`. It prints the folder as `/golden/<folder>`.

It then compares every file the store wrote with the golden file, byte for byte:

- `feedback.json`
- `manifest.md`
- `prompt.md`
- one `<stem>-prompt.md` per capture

A file the store writes with no golden twin fails the test. A golden file the store does not write fails the test. The exceptions are `selection-prompt.md`, `zip-readme.md`, and `timezone.txt`. The store does not write them.

## How to change a golden file

1. Change the Swift code in `Packages/FeedbackKit`.
2. Run `UPDATE_GOLDEN=1 swift test --package-path Packages/FeedbackKit --filter GoldenBundleTests`.
3. Read the diff in `Windows/golden/`. Commit the goldens.
4. Run `DOTNET_ROLL_FORWARD=Major dotnet test Windows/tests/Nextshot.Core.Tests`.
5. Fix the C# code until the test passes.

Never edit a golden file by hand. Never change the C# code to match a wrong golden file.

## CI

Both CI jobs must stay green. The Mac job runs `GoldenBundleTests` and fails when Swift output differs from the goldens. The Windows job runs `dotnet test` and fails when C# output differs from the goldens. A Swift change with new goldens and no C# fix turns the Windows job red.
