# Nextshot Dev extension: local pilot

This package is a development artifact. The Chrome work stays in Later and outside v0.5.0. There is no Web Store upload or public release. The Mac app is optional for browser capture, local save, and export.

## Build the package

From the repository root, run:

```bash
python3 -I browser-extension/package-dev.py
```

The script installs locked build dependencies, checks TypeScript, and builds a clean extension. It writes `build/browser-extension-package/Nextshot-Dev-extension-0.1.0.zip` and its SHA-256 file. Sorted entries, fixed timestamps, and fixed file permissions make repeated builds reproducible for the same source and tool versions. `package-audit.json` records source commit, file hashes, permissions, and HTTP address literals. Review that inventory when a network path changes.

The package contains browser files and the existing helper registration script. It contains no native executable, saved browser data, credentials, or pilot account configuration. Building does not install into Chrome or change app flags.

## Load the Dev extension

1. Extract the ZIP into a stable project folder. Keep its `extension` folder intact.
2. Open `chrome://extensions` in the Chrome profile used for this pilot.
3. Enable Developer mode. Choose Load unpacked and select the extracted `extension` folder.
4. Verify the extension name is Nextshot Dev. Its exact ID is `ghmidcmcjigfckaiopacgpfaffofgjel`.
5. Pin it to the toolbar. Reload it from the extensions page after replacing its files.

Required permissions are activeTab, scripting, and storage. Site access remains optional and is requested for the chosen site. Recording also requests offscreen access. Native messaging remains optional. Capture no passwords, private customer data, or production data in the smoke test. Fields and embedded frames receive masks, but masking cannot detect every private value.

Recording, Rolling Round, native delivery, and optional AI start disabled. Enabling one trial does not enable the others. Optional AI needs its own configuration, consent, and supported account or local model. It never blocks browser saving.

## Optional native save

Use only the signed Nextshot Dev app on this Mac. The installed app must include its signed browser helper. The package does not install the app.

From the extracted package root, register that exact helper:

```bash
python3 -I tools/register-browser-host.py "$HOME/Applications/Nextshot Dev.app"
```

The command verifies the Dev app identity and signatures. It registers `com.drewschulz.nextshot.dev.browser` for the exact extension ID above in this user's normal Google Chrome profile directory. It does not configure Chromium or Chrome for Testing.

From the repository root, opt into the native trial, then reopen Nextshot Dev through the local policy check:

```bash
scripts/nextshot-flags.sh set browserBridge on
python3 -I scripts/nextshot-local.py check
python3 -I scripts/nextshot-local.py open
```

Enable optional native saving in the extension. Browser saving still succeeds if native delivery fails. Restore the native default after the trial with `scripts/nextshot-flags.sh reset browserBridge` and reopen Dev normally.

## Smoke checklist

Use a controlled local or staging page with a button, a visible failure message, and a harmless form field.

| Check | Expected result |
|---|---|
| Standalone capture | Choose Capture an area, approve the site, mark the screenshot, add a note, and click Done. It saves and copies the prompt without the Mac app. |
| Context and masks | The mark matches the intended element. The harmless form field is covered in saved evidence. Missing source context remains explicit. |
| Export | Export the saved browser round. The ZIP has relative paths, readable notes, and the selected images. |
| Native optional | Enable native saving and save a fresh capture. Nextshot Dev imports it. Repeated delivery does not duplicate it. |
| Explicit recording | Enable its trial, record several controlled actions, stop, and select an excerpt. The silent animation decodes. Coverage gaps remain labeled. |
| Rolling history | Enable Rolling Round and arm the current tab. Record at least 60 active seconds. Leaving the tab pauses collection. Returning resumes it. |
| Site boundary | Navigate on the same site, then to another site. Same-origin collection recovers. Cross-site collection needs explicit re-arm and permission. |
| Selected ten seconds | Open Rolling Round. Mark the failure first. Choose about ten seconds and review the observed steps. Continue to marks and notes, then save. |
| Selected package | Verify key frames, steps, diagnostics, and any animation stay within the selected interval. Animation can be omitted automatically. No size question appears. |
| Round ownership | Keep an ordinary round active before the rolling save. The rolling result forms a separate ended round. The ordinary round remains active. |
| Cleanup | Cancel review and return to the source. Then Stop. Unsaved history and extracted review copies clear. Saved rounds remain available. |
| Lifecycle | Close the source tab or revoke its site permission. Unsaved rolling history clears. Re-arm explicitly before a new trial. |

Sampling runs at most once per second. Page changes can skip frames. There is no audio or typed-value collection. Lightweight diagnostics do not provide full console or network coverage. Review has no inactivity timer. Browser restart clears unsaved history. A worker restart preserves valid in-memory review evidence while the browser stays open.

## Finish the pilot

Stop recording and rolling tracking before disabling their trials. Turn off optional native and AI settings. Reset the native `browserBridge` override if enabled. To unload this local extension, disable or remove Nextshot Dev on `chrome://extensions`. Extension removal also removes its browser storage, so export any saved browser rounds first.

The optional native registration file is `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.drewschulz.nextshot.dev.browser.json`. Remove that specific file only when ending native helper use. Keep Nextshot rounds and saved exports intact.
