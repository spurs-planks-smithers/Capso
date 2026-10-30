# N1 spikes (issue 178)

Throwaway feasibility code for [#178](https://github.com/spurs-planks-smithers/Capso/issues/178). None of it ships. The findings are in [../2026-10-30-native-trigger-and-review-transport.md](../2026-10-30-native-trigger-and-review-transport.md).

| Folder or file | Spike | What it runs |
| --- | --- | --- |
| `helper_states.py` | 2 | The installed `NextshotBrowserHost` driven over native-messaging stdio, as Chrome does |
| `discover.swift` | 2 | Prototype that tells apart absent, incompatible, disabled, closed and running with no app launch |
| `transport/` | 3 | Stand-in app and host joined by one held Apple Event, plus a Python stand-in for Chrome |
| `chromium/` | 1, 3 | A throwaway extension in Chrome for Testing that opens a native port, with the same host |
| `trigger/permissions.swift` | 1 | Reads macOS permission state, no prompt |
| `media/` | 4 | AVFoundation probe, fixture clips, and a MediaRecorder run in the installed Chrome binary |
| `results/` | all | Raw output of each run |

Evidence tiers used in the findings: **fixture** (a stand-in or a throwaway profile), **installed** (the installed Nextshot Dev app or the installed Chrome binary, never Drew's Chrome profile), **not observed**.

Run order and commands:

```bash
# Build and sign the transport spike (uses the Apple Development identity)
bash docs/research/2026-10-30-n1-spikes/transport/build.sh /tmp/n1-spike
python3 -I docs/research/2026-10-30-n1-spikes/transport/harness.py /tmp/n1-spike 30
# Real Chromium engine lifecycle (needs a playwright-core copy and Chrome for Testing)
PLAYWRIGHT_CORE=/path/to/playwright-core/index.mjs CFT_PATH="/path/to/Google Chrome for Testing" \
  node docs/research/2026-10-30-n1-spikes/chromium/run.mjs /tmp/n1-spike /tmp/n1-chromium
```

The helper probe and the discovery prototype read the installed Nextshot Dev app. The probe flips `flag.browserBridge` for a few seconds to observe the disabled state, then restores it.
