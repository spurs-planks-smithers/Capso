# Duplicates and conflicts: live eval results, 2026-10-24

Part A of `docs/superpowers/plans/2026-10-24-dupes-conflicts-test-plan.md`. Run with `scripts/jev-eval-dupes.sh` at commit `634b712`, model `jev-1.14.0`, on 2026-10-24 at 18:58 PDT. 60 labeled made-up cases and 2 real pairs, 4 data arms, 3 runs each: 726 requests, 0 failed, 23 seconds in all.

## Result

- Notes only (A1) fails the bar. Duplicate precision is 0.53: all 8 X cases and S4 (the same words for two different elements) were called duplicates. Conflict precision is 0.80: three P cases (opposite changes on different elements) were called conflicts. No code variant fixes this. V2w reaches 0.71.
- Notes and screen text (A2) meets the bar. 11 of 11 duplicate calls and 12 of 12 conflict calls are right. Recall: 0.85 for duplicates, 0.92 for conflicts. No X case is called a duplicate. Five different pairs get an overlap line, which only asks the agent to check the code.
- Notes, screen text, and images (A3) is the best arm. 12 of 12 duplicate calls and 12 of 12 conflict calls are right, and all 26 different cases are called different. Recall: 0.92 for both. It costs about 5.7 times the input tokens of A2 (4,044 against 708 per request) and 155 ms against 97 ms.
- Images for every pair (A4) adds nothing over A3.
- The stricter duplicate cut points (V3a 1.6, V3b 1.7) lower recall and raise no precision. The cut point stays at 1.5.
- Stability: 95% to 100% of cases gave the same call in all three runs.
- One known gap: N3, a general note "Rename session to round everywhere" against "Rename this row to Copy Session Prompt", is never called a conflict.
- Real pairs, notes only: R1 (3.2 and 4.2 of round 2026-10-22-1839) is an overlap, as expected. R2 (1.2 and 2.1 of round 2026-10-21-1541) gets an overlap line where "different" was expected, a harmless check line.
- Cost: about 1.8M input tokens for the whole eval, about $0.07.

## Limits

- The images are plain screenshots of the test pages, with no drawn badges. Each crop centers on the marked element.
- The cases are made up and short. Drew's real notes are longer and often hold several asks.

## Full report

The report the suite wrote follows unchanged.

# Duplicates and conflicts live eval

Generated 2026-10-25T01:58:44Z. Model jev-1.14.0. 726 runs: 3 per case and arm. Arms: A1, A2, A3, A4.

A run whose request failed is not checked and is never a call. Recall counts checked runs and cases only. The majority call of a case is the call that more than half of its checked runs made. A case with no majority is split: it counts in recall as a miss and makes no call.

Real pair R1 (round 2026-10-22-1839-feedback, items 3.2 and 4.2) ran in A1.

Real pair R2 (round 2026-10-21-1541-feedback, items 1.2 and 2.1) ran in A1.

## 1. Precision and recall by arm and variant

The bar for each call type: at least 10 calls and at most 1 wrong in 10. Real pairs R1 and R2 count in A1 only. Basis runs counts every checked run. Basis cases counts the majority call of each case.

| Arm | Variant | Basis | Dup calls | Dup right | Dup precision | Dup recall | Conflict calls | Conflict right | Conflict precision | Conflict recall | X called dup | Dup bar | Conflict bar |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | V1 | runs | 57 | 30 | 0.53 | 0.77 | 45 | 36 | 0.80 | 0.92 | 24 | no | no |
| A1 | V1 | cases | 19 | 10 | 0.53 | 0.77 | 15 | 12 | 0.80 | 0.92 | 8 | no | no |
| A1 | V2 | runs | 48 | 30 | 0.62 | 0.77 | 45 | 36 | 0.80 | 0.92 | 15 | no | no |
| A1 | V2 | cases | 16 | 10 | 0.62 | 0.77 | 15 | 12 | 0.80 | 0.92 | 5 | no | no |
| A1 | V2w | runs | 42 | 30 | 0.71 | 0.77 | 45 | 36 | 0.80 | 0.92 | 9 | no | no |
| A1 | V2w | cases | 14 | 10 | 0.71 | 0.77 | 15 | 12 | 0.80 | 0.92 | 3 | no | no |
| A1 | V3a | runs | 56 | 30 | 0.54 | 0.77 | 45 | 36 | 0.80 | 0.92 | 23 | no | no |
| A1 | V3a | cases | 19 | 10 | 0.53 | 0.77 | 15 | 12 | 0.80 | 0.92 | 8 | no | no |
| A1 | V3b | runs | 51 | 29 | 0.57 | 0.74 | 45 | 36 | 0.80 | 0.92 | 19 | no | no |
| A1 | V3b | cases | 17 | 10 | 0.59 | 0.77 | 15 | 12 | 0.80 | 0.92 | 6 | no | no |
| A2 | V1 | runs | 33 | 33 | 1.00 | 0.85 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A2 | V1 | cases | 11 | 11 | 1.00 | 0.85 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A2 | V2 | runs | 33 | 33 | 1.00 | 0.85 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A2 | V2 | cases | 11 | 11 | 1.00 | 0.85 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A2 | V2w | runs | 33 | 33 | 1.00 | 0.85 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A2 | V2w | cases | 11 | 11 | 1.00 | 0.85 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A2 | V3a | runs | 33 | 33 | 1.00 | 0.85 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A2 | V3a | cases | 11 | 11 | 1.00 | 0.85 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A2 | V3b | runs | 33 | 33 | 1.00 | 0.85 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A2 | V3b | cases | 11 | 11 | 1.00 | 0.85 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V1 | runs | 35 | 35 | 1.00 | 0.90 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V1 | cases | 12 | 12 | 1.00 | 0.92 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V2 | runs | 35 | 35 | 1.00 | 0.90 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V2 | cases | 12 | 12 | 1.00 | 0.92 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V2w | runs | 35 | 35 | 1.00 | 0.90 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V2w | cases | 12 | 12 | 1.00 | 0.92 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V3a | runs | 33 | 33 | 1.00 | 0.85 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V3a | cases | 11 | 11 | 1.00 | 0.85 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V3b | runs | 33 | 33 | 1.00 | 0.85 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A3 | V3b | cases | 11 | 11 | 1.00 | 0.85 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V1 | runs | 35 | 35 | 1.00 | 0.90 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V1 | cases | 12 | 12 | 1.00 | 0.92 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V2 | runs | 35 | 35 | 1.00 | 0.90 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V2 | cases | 12 | 12 | 1.00 | 0.92 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V2w | runs | 35 | 35 | 1.00 | 0.90 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V2w | cases | 12 | 12 | 1.00 | 0.92 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V3a | runs | 34 | 34 | 1.00 | 0.87 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V3a | cases | 11 | 11 | 1.00 | 0.85 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V3b | runs | 33 | 33 | 1.00 | 0.85 | 36 | 36 | 1.00 | 0.92 | 0 | yes | yes |
| A4 | V3b | cases | 11 | 11 | 1.00 | 0.85 | 12 | 12 | 1.00 | 0.92 | 0 | yes | yes |

## 2. Expected call by actual call (V1, majority call of each case)

Arm A1. Rows are the expected call, columns the actual call.

| Expected | duplicate | overlap | conflict | different | split | not checked |
| --- | --- | --- | --- | --- | --- | --- |
| duplicate | 10 | 3 | 0 | 0 | 0 | 0 |
| overlap | 0 | 9 | 0 | 0 | 0 | 0 |
| conflict | 0 | 1 | 12 | 0 | 0 | 0 |
| different | 9 | 4 | 3 | 11 | 0 | 0 |

Arm A2. Rows are the expected call, columns the actual call.

| Expected | duplicate | overlap | conflict | different | split | not checked |
| --- | --- | --- | --- | --- | --- | --- |
| duplicate | 11 | 2 | 0 | 0 | 0 | 0 |
| overlap | 0 | 8 | 0 | 0 | 0 | 0 |
| conflict | 0 | 1 | 12 | 0 | 0 | 0 |
| different | 0 | 5 | 0 | 21 | 0 | 0 |

Arm A3. Rows are the expected call, columns the actual call.

| Expected | duplicate | overlap | conflict | different | split | not checked |
| --- | --- | --- | --- | --- | --- | --- |
| duplicate | 12 | 1 | 0 | 0 | 0 | 0 |
| overlap | 0 | 8 | 0 | 0 | 0 | 0 |
| conflict | 0 | 0 | 12 | 1 | 0 | 0 |
| different | 0 | 0 | 0 | 26 | 0 | 0 |

Arm A4. Rows are the expected call, columns the actual call.

| Expected | duplicate | overlap | conflict | different | split | not checked |
| --- | --- | --- | --- | --- | --- | --- |
| duplicate | 12 | 1 | 0 | 0 | 0 | 0 |
| overlap | 0 | 8 | 0 | 0 | 0 | 0 |
| conflict | 0 | 0 | 12 | 1 | 0 | 0 |
| different | 0 | 0 | 0 | 26 | 0 | 0 |

## 3. Every case

Each arm cell is the V1 majority call, then the mean sameAsk and the mean opposite of the checked runs. [!] marks a case whose checked runs gave different V1 calls.

| Case | Group | Expected | A1 | A2 | A3 | A4 |
| --- | --- | --- | --- | --- | --- | --- |
| D1 | D | duplicate | duplicate (1.95, 0.05) | duplicate (1.99, 0.04) | duplicate (1.98, 0.04) | duplicate (1.98, 0.05) |
| D2 | D | duplicate | overlap (1.30, 0.12) | overlap (1.43, 0.04) | duplicate (1.86, 0.03) | duplicate (1.86, 0.03) |
| D3 | D | duplicate | duplicate (1.85, 0.12) | duplicate (1.98, 0.05) | duplicate (1.98, 0.07) | duplicate (1.98, 0.06) |
| D4 | D | duplicate | duplicate (1.81, 0.07) | duplicate (1.98, 0.04) | duplicate (1.95, 0.05) | duplicate (1.95, 0.04) |
| D5 | D | duplicate | duplicate (1.95, 0.06) | duplicate (1.92, 0.03) | duplicate (1.98, 0.04) | duplicate (1.98, 0.04) |
| D6 | D | duplicate | duplicate (1.99, 0.06) | duplicate (1.99, 0.04) | duplicate (1.99, 0.04) | duplicate (1.99, 0.04) |
| D7 | D | duplicate | duplicate (1.79, 0.16) | duplicate (1.85, 0.10) | overlap (1.09, 0.22) | overlap (1.29, 0.26) |
| D8 | D | duplicate | overlap (1.33, 0.33) | duplicate (1.84, 0.12) | duplicate (1.95, 0.15) | duplicate (1.96, 0.14) |
| D9 | D | duplicate | duplicate (1.90, 0.10) | duplicate (1.97, 0.04) | duplicate (1.95, 0.04) | duplicate (1.94, 0.04) |
| D10 | D | duplicate | duplicate (1.73, 0.14) | duplicate (1.96, 0.05) | duplicate (1.94, 0.09) | duplicate (1.94, 0.09) |
| D11 | D | duplicate | duplicate (1.99, 0.05) | duplicate (1.99, 0.03) | duplicate (1.98, 0.04) | duplicate (1.98, 0.03) |
| D12 | D | duplicate | overlap (0.87, 0.26) | overlap (1.34, 0.33) | duplicate (1.51, 0.39) [!] | duplicate (1.51, 0.40) [!] |
| X1 | X | different | duplicate (1.88, 0.04) | different (0.25, 0.19) | different (0.29, 0.11) | different (0.25, 0.11) |
| X2 | X | different | duplicate (1.92, 0.08) | different (0.36, 0.18) | different (0.34, 0.17) | different (0.46, 0.13) [!] |
| X3 | X | different | duplicate (1.75, 0.06) | different (0.25, 0.13) | different (0.22, 0.06) | different (0.20, 0.05) |
| X4 | X | different | duplicate (1.98, 0.04) | different (0.28, 0.15) | different (0.38, 0.18) | different (0.38, 0.20) |
| X5 | X | different | duplicate (1.66, 0.11) | different (0.21, 0.10) | different (0.12, 0.10) | different (0.12, 0.11) |
| X6 | X | different | duplicate (1.99, 0.04) | overlap (0.59, 0.09) | different (0.24, 0.15) | different (0.26, 0.13) |
| X7 | X | different | duplicate (1.99, 0.03) | different (0.37, 0.23) | different (0.39, 0.24) | different (0.34, 0.15) |
| X8 | X | different | duplicate (1.66, 0.11) | overlap (0.53, 0.13) | different (0.48, 0.14) [!] | different (0.31, 0.10) |
| O1 | O | overlap | overlap (1.08, 0.05) | overlap (1.07, 0.04) | overlap (1.03, 0.04) | overlap (1.06, 0.04) |
| O2 | O | overlap | overlap (1.09, 0.05) | overlap (1.06, 0.04) | overlap (1.05, 0.04) | overlap (1.06, 0.04) |
| O3 | O | overlap | overlap (1.03, 0.09) | overlap (1.02, 0.08) | overlap (1.04, 0.11) | overlap (1.04, 0.14) |
| O4 | O | overlap | overlap (1.05, 0.04) | overlap (1.08, 0.03) | overlap (1.08, 0.03) | overlap (1.07, 0.04) |
| O5 | O | overlap | overlap (1.10, 0.08) | overlap (1.11, 0.05) | overlap (1.15, 0.11) | overlap (1.17, 0.13) |
| O6 | O | overlap | overlap (1.07, 0.06) | overlap (1.12, 0.03) | overlap (1.13, 0.04) | overlap (1.12, 0.04) |
| C1 | C | conflict | conflict (0.76, 0.97) | conflict (0.59, 0.96) | conflict (0.47, 0.98) | conflict (0.50, 0.98) |
| C2 | C | conflict | conflict (0.89, 0.93) | conflict (0.71, 0.95) | conflict (0.61, 0.96) | conflict (0.60, 0.96) |
| C3 | C | conflict | conflict (0.71, 0.96) | conflict (0.62, 0.95) | conflict (0.72, 0.96) | conflict (0.71, 0.97) |
| C4 | C | conflict | conflict (0.44, 0.94) | conflict (0.29, 0.96) | conflict (0.18, 0.97) | conflict (0.19, 0.97) |
| C5 | C | conflict | conflict (0.66, 0.92) | conflict (0.33, 0.95) | conflict (0.28, 0.97) | conflict (0.26, 0.97) |
| C6 | C | conflict | conflict (0.85, 0.97) | conflict (0.49, 0.95) | conflict (0.36, 0.97) | conflict (0.35, 0.97) |
| C7 | C | conflict | conflict (0.62, 0.85) | conflict (0.38, 0.85) | conflict (0.23, 0.94) | conflict (0.22, 0.93) |
| C8 | C | conflict | conflict (1.07, 0.95) | conflict (0.78, 0.95) | conflict (0.75, 0.95) | conflict (0.73, 0.95) |
| C9 | C | conflict | conflict (0.61, 0.95) | conflict (0.36, 0.92) | conflict (0.38, 0.92) | conflict (0.45, 0.93) |
| C10 | C | conflict | conflict (0.68, 0.92) | conflict (0.56, 0.94) | conflict (0.41, 0.91) | conflict (0.39, 0.94) |
| B1 | B | different | overlap (0.53, 0.20) | overlap (0.56, 0.11) | different (0.18, 0.09) | different (0.17, 0.09) |
| B2 | B | different | overlap (0.79, 0.09) | overlap (0.62, 0.08) | different (0.26, 0.06) | different (0.24, 0.06) |
| B3 | B | different | different (0.03, 0.03) | different (0.01, 0.03) | different (0.01, 0.03) | different (0.01, 0.03) |
| B4 | B | different | overlap (0.70, 0.11) | overlap (0.54, 0.46) [!] | different (0.42, 0.42) | different (0.38, 0.38) |
| P1 | P | different | conflict (0.72, 0.94) | different (0.23, 0.45) | different (0.20, 0.30) | different (0.16, 0.30) |
| P2 | P | different | conflict (0.66, 0.91) | different (0.11, 0.11) | different (0.06, 0.05) | different (0.06, 0.06) |
| P3 | P | different | different (0.23, 0.57) | different (0.18, 0.46) | different (0.13, 0.57) | different (0.12, 0.60) |
| P4 | P | different | conflict (0.61, 0.91) | different (0.31, 0.58) | different (0.25, 0.28) | different (0.28, 0.24) |
| U1 | U | different | different (0.01, 0.04) | different (0.02, 0.05) | different (0.01, 0.04) | different (0.01, 0.04) |
| U2 | U | different | different (0.01, 0.06) | different (0.01, 0.05) | different (0.01, 0.02) | different (0.01, 0.03) |
| U3 | U | different | different (0.00, 0.06) | different (0.01, 0.08) | different (0.01, 0.04) | different (0.01, 0.04) |
| U4 | U | different | different (0.01, 0.06) | different (0.01, 0.04) | different (0.05, 0.04) | different (0.04, 0.04) |
| U5 | U | different | different (0.02, 0.04) | different (0.01, 0.04) | different (0.01, 0.04) | different (0.01, 0.03) |
| U6 | U | different | different (0.01, 0.04) | different (0.01, 0.03) | different (0.01, 0.03) | different (0.01, 0.02) |
| S1 | S | conflict | conflict (0.79, 0.96) | conflict (0.55, 0.96) | conflict (0.47, 0.97) | conflict (0.51, 0.98) |
| S2 | S | duplicate | duplicate (1.97, 0.08) | duplicate (1.99, 0.04) | duplicate (1.98, 0.04) | duplicate (1.99, 0.03) |
| S3 | S | different | different (0.00, 0.03) | different (0.01, 0.06) | different (0.01, 0.02) | different (0.01, 0.02) |
| S4 | S | different | duplicate (1.98, 0.04) | different (0.32, 0.14) | different (0.39, 0.17) | different (0.39, 0.16) |
| S5 | S | overlap | overlap (1.08, 0.04) | overlap (1.11, 0.03) | overlap (1.03, 0.04) | overlap (1.03, 0.04) |
| S6 | S | different | different (0.02, 0.04) | different (0.01, 0.04) | different (0.01, 0.02) | different (0.01, 0.02) |
| N1 | N | overlap | overlap (1.21, 0.07) | overlap (0.98, 0.06) | overlap (1.38, 0.09) | overlap (1.40, 0.08) |
| N2 | N | conflict | conflict (0.43, 0.76) | conflict (0.57, 0.97) | conflict (0.38, 0.96) | conflict (0.41, 0.97) |
| N3 | N | conflict | overlap (0.52, 0.44) | overlap (0.72, 0.37) | different (0.48, 0.23) [!] | different (0.47, 0.22) |
| N4 | N | different | different (0.01, 0.03) | different (0.03, 0.05) | different (0.03, 0.05) | different (0.01, 0.03) |
| R1 | R | overlap | overlap (1.16, 0.15) | n/a | n/a | n/a |
| R2 | R | different | overlap (1.17, 0.09) | n/a | n/a | n/a |

## 4. Stability

The share of cases whose runs all gave the same V1 call. Cases with a not-checked run are left out.

| Arm | Same V1 call in every run |
| --- | --- |
| A1 | 100.0% (62 of 62) |
| A2 | 98.3% (59 of 60) |
| A3 | 95.0% (57 of 60) |
| A4 | 96.7% (58 of 60) |

## 5. Requests, failures, time, and tokens

Mean milliseconds and mean input tokens are over requests that succeeded.

| Arm | Requests | Failed | Not checked runs by reason | Images sent | Mean milliseconds | Mean input tokens |
| --- | --- | --- | --- | --- | --- | --- |
| A1 | 186 | 0 | n/a | 0 | 98 | 603 |
| A2 | 180 | 0 | n/a | 0 | 97 | 708 |
| A3 | 180 | 0 | n/a | 324 | 155 | 4044 |
| A4 | 180 | 0 | n/a | 360 | 154 | 4477 |
