# Chrome pilot performance evidence

Date: October 29, 2026. This is one bounded local measurement, not a production performance budget. Chrome remains in Later and outside v0.5.0.

### Steady idle

Source: 9523e7a215afabde4823408a561a9fc709ba1b91. Two owned Chrome for Testing profiles use the same synthetic page and window dimensions. This test opens no private Artifact.

The extension uses its exact built manifest. No test permission is added. The setup page closes before sampling. The worker naturally stops after 30 seconds. No offscreen document or recording remains. Each browser supplies ten one-second measurement intervals after quiet waiting.

| Whole browser tree | Baseline | Extension |
|---|---:|---:|
| Mean processor use | 0.048% | 0.655% |
| Median interval processor use | 0.003% | 0.116% |
| Mean physical footprint | 367.31 MiB | 375.23 MiB |
| Package idle wakeups per second | 0.000 | 0.100 |
| Interrupt wakeups per second | 1.589 | 2.289 |

One processor core is 100%. A mebibyte (MiB) is 1,048,576 bytes. Physical footprint is summed across the owned browser process tree.

The observed difference is 7.92 MiB of whole-browser footprint. The highest extension interval uses 3.326% of one core. These values do not isolate extension allocation or establish a precise recurring cost. They do not measure battery drain or energy.

### Active workflow

Source: 01dfd8a8d514ccfd212a8778aa800b8c79c35cb1. These measurements precede the clock and resource-warning corrections. The fixture pregrants site and offscreen access. Actual permission prompts are verified separately in regular Chrome.

| Operation | Elapsed time |
|---|---:|
| Capture gesture to ready review | 214 milliseconds |
| Arm Rolling Round | 87 milliseconds |
| Selected excerpt to ready review | 336 milliseconds |
| Selected export download | 60 milliseconds |
| ZIP creation alone | 1.5 milliseconds |

The selected package contains 78,302 bytes. Its synthetic interval lasts 1,212 milliseconds and contains two key frames and silent WebM media. It contains no accepted steps after its pause gap.

| State | Mean processor use | Mean physical footprint |
|---|---:|---:|
| Rolling armed | 6.83% | 962.0 MiB |
| Rolling paused | 0.28% | 751.3 MiB |
| Rolling review | 0.77% | 777.7 MiB |

These active-state samples include the browser and an inactive control page. Startup activity affects them. They do not establish an extension memory limit. The steady-idle pass above replaces the initial idle comparison.

### Method and limits

The sampler reads only owned browser processes and descendants. It uses unprivileged libproc counters. Processor time applies the Mach timebase conversion. Wakeups use direct process counters. No machine-wide energy estimate is inferred.

Fresh profiles, a single synthetic site, headless execution, and measurement order limit the result. Permission latency and long-duration resource growth require later pilot measurements. Required Chrome indicators remain visible during real tracking.

Both passes close their browsers and servers. All sampled process IDs are absent after cleanup. Recording Stop closes its offscreen document. Regular Chrome and Drew's handoff remain outside these performance tests.

Raw samples, source inventories, harnesses, and cleanup evidence remain in `build/chrome-execution/performance/`. This ignored folder contains synthetic test data. The execution record names the final source and user acceptance state.
