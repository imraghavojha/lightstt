# Performance measurements

These are observations of two installed configurations on one machine, not a general ranking or a comparison of equivalent inference engines. LightTTS used Parakeet TDT 0.6B v3; SuperWhisper used Whisper Large v3 Turbo. SuperWhisper's interface showed its Parakeet options locked, so no matching model was downloaded or tested. Three short sentences are too few to establish accuracy or a reliable latency distribution.

## Final signed release

The installed release built from `86c17b6d452c480c967339338509ab6bfccb7681` has the same production source as merged `998e760612a0743a3c6e2ead2cc6bd698942e852`. Its allocated bundle size is 45,896 KiB (44.82 MiB), excluding downloaded models. The installed SuperWhisper bundle measured 140,172 KiB (136.89 MiB): this LightTTS bundle is about 67% smaller. Strict deep signature verification passed with the existing designated signing identity. The executable UUID was `87942425-DF17-3CBA-8B40-67F8DAA64868`.

Three final LightTTS trials using the same fixtures and 20 ms, stop-release-based AX polling described below took 175.7, 375.2 and 268.1 ms (median 268.1 ms). The corresponding earlier SuperWhisper trials took 466.6, 426.9 and 460.9 ms (median 460.9 ms). Both configurations misrecognized the name sentence. The final LightTTS actual second transcript was “Please send a report to MITU at 9.30 tomorrow morning.” The different selected models and small sample prevent a general speed or accuracy ranking; these measurements do not isolate the effect of any one code change.

Both apps also received 60-second **post-dictation** samples, with 13 observations about five seconds apart. CPU comes from interval cumulative-time differences; the initial sample is excluded. Current neural memory is separate from physical footprint and historical neural peak.

| Post-dictation observation | Final LightTTS app and helper | SuperWhisper |
| --- | --- | --- |
| Physical footprint, first → last | 46 → 46 MB | 1,857 → 256 MB |
| Interval CPU mean (range) | 0.016% (0–0.195%) | 3.33% (2.53–6.64%) |
| Separately reported current neural memory, first → last | 471 MB → 64 KB | Not reported |
| Historical neural peak | 475 MB | Not reported |

These changing residency figures are not inference peaks or a battery-life measurement. Shared system services were not attributed. A further SuperWhisper toggle trial completed in 464.1 ms; a preceding attempt inserted only “Standing on the wooden fence.” Neither failed nor truncated attempts were discarded from the evidence.

The final full local checks and installed acceptance passed: TextEdit, Chrome, popup lifecycle, Escape cancellation and idle CPU. Notes and Finder were skipped because safe targets could not be uniquely identified. Live checks reproduced and verified repairs for closing Settings during shortcut capture and resizing below its minimum, then exercised shortcut editing, reset, toggle and push-to-talk. Menu Start → full sentence → menu Stop subsequently inserted the expected sentence into the intended TextEdit document; Settings opened, closed and reopened from the menu. The earlier menu automation omitted click state and an explicit HID source; correcting synthetic input exposed the popover without an app change.

Three distinct-sentence pairs for each close-after preference, plus two pasteboard-watcher pairs per preference, retained both history entries during copy-only retries. One earlier untraced immediate retry failed and its cause remains unknown. The successful watcher trials did not deliver the second shortcut inside the exact clipboard-write/commit interval, so that scheduling boundary is not independently proven race-free. Minimize was invoked and Settings reopened, but the intermediate minimized state was not captured. These limits remain explicit rather than being counted as passes.

Raw local evidence: `/tmp/lighttts-final-release-evidence/` and `/tmp/lighttts-two-flows-evidence/`; reports: `/tmp/lighttts-final-release-verification.md` and `/tmp/lighttts-final-two-flows.md`. Preferences and clipboard were restored, and the installed app was relaunched without test or trace environment.

## Same-machine comparison

On October 30, 2026, an Apple M1 Max MacBook Pro with 64 GB RAM, macOS 27.0.1, and AC power ran the signed release of LightTTS commit `9edc170c85b773b61cc64ff1164c85d4eb63c9a0` and installed SuperWhisper 3.1.0. The apps ran sequentially, not concurrently. Both selected the default MacBook Pro microphone; output volume was 19. Allocated disk usage is from `du -sk`, rounded to MiB or GiB. Models are outside the application bundles and are not included in bundle sizes.

| Observation | LightTTS | SuperWhisper |
| --- | --- | --- |
| App bundle | 68 MiB | 137 MiB |
| Selected model storage | Parakeet v3 directory: 461 MiB | Local `ggml-large-v3-turbo.bin`: 1.51 GiB |
| All downloaded model storage observed | Models directory: 3.06 GiB | Five `ggml-*.bin` files: 6.73 GiB |
| Idle physical footprint, process tree, excluding separately reported neural memory | 49 MB after dictation | 107 MB before successful dictation |
| Idle interval CPU, process tree | After dictation: 0.03% mean, 0–0.20% range | Before successful dictation: 1.81% mean, 1.18–3.92% range |
| Separately reported neural memory during idle | Current 471 MB initially, then 64 KB; historical peak 475 MB | Not reported by `footprint` |

Idle measurements used `scripts/perf/process-sample.py` at five-second intervals for 60 seconds, with recording, processing, and settings menus closed. CPU is calculated from cumulative process CPU time; the first sample has no interval and is excluded from the mean. LightTTS's app and inference helper were included. SuperWhisper had one observed process and no separately named helper in the process listing. This does not measure shared system services. The LightTTS sample followed dictation; SuperWhisper's preceded its successful trials. SuperWhisper's single post-trial `footprint` snapshot was 1,873 MB; it is not an inference peak. No neural value was printed for it. The LightTTS neural peak is historical for that process, not a measurement of the peak during a particular trial. These figures do not establish battery life.

The operator synthesized each sentence once with `say`, played the same audio files through the speakers for both apps in the same order, and waited for playback to finish before stopping. Each trial used a fresh, empty, uniquely named TextEdit document. Both successful sets used Option-Space toggle. A single process posted the stop shortcut, timestamped the final key release, and polled the identified text field's accessibility value every 20 ms until the first inserted text. The stop action occurs on key-down before that final release, so these values are not directly comparable to timings measured from key-down. Polling and event scheduling limit precision. There was no cold-start control: LightTTS had already transcribed acceptance utterances, while SuperWhisper had been launched and had unsuccessful shortcut attempts before the toggle trials. Model residency during each inference was not independently observed.

| Reference | LightTTS actual (ms) | SuperWhisper actual (ms) |
| --- | --- | --- |
| The little green bird landed on the wooden fence. | The little green bird landed on the wooden fence. (263) | The little green bird landed on the wooden fence (467) |
| Please send the report to Maya at nine thirty tomorrow morning. | Please send a report to MADIU at nine thirty tomorrow morning. (368) | Please send the report to my at 9 30 tomorrow morning (427) |
| Daniel has 42 blue notebooks and 17 red pencils. | Daniel has 42 blue notebooks and 17 red pencils. (335) | Daniel has 42 blue notebooks and 17 red pencils (461) |

For these three successful insertions, median and range were 335 ms (263–368 ms) for LightTTS and 461 ms (427–467 ms) for SuperWhisper. The second sentence contains recognition errors in both outputs; punctuation and number formatting also differ. These are end-to-end observations under the stated models and conditions, not isolated inference timings.

SuperWhisper's settings also showed an Option-only push-to-talk shortcut. Three synthetic held-Option attempts produced no text within 30 seconds each; the subsequent configured toggle shortcut worked. The failed attempts have no latency or accuracy result. This establishes a limit of this automation, not the cause of the failure or a product defect.

The installed LightTTS acceptance script passed its TextEdit and Chrome paste, popup lifecycle, Escape cancellation, and idle CPU checks; its Notes and Finder cases were skipped because uniquely identifiable targets were unavailable. Its polling timings are separate from the comparison above.

## Scoped encoding benchmark

A prior release-compiled WAV encoding microbenchmark on the same machine used a fixed synthetic 16 kHz mono PCM16 fixture (SHA-256 `0d7d0d63c5f6ad339d12e008657d0866d093a75bb71595ee3ba2ab622ff1db5c`). Across 101 calls, the old encoder had a 0.695 ms median and 0.845 ms p95; bulk encoding had a 0.003 ms median and 0.003 ms p95. The benchmark checks byte equality and can be run with `scripts/perf/benchmark-wav.sh <fixture.wav>`. Encoding happens after insertion; this is not a measured improvement to stop-to-visible latency.

## Delivery and history lifecycle

After delivery, the controller commits the transcript before serial history preparation and accepts the next recording immediately, including while completion feedback is visible. The close-after preference controls dismissal; copied feedback remains visible for one second when enabled. Normal application termination waits for queued history writes instead of exiting on a two-second deadline. Delayed-preparation regression checks cover the next recording, cancellation, both completion preferences, deletion, migration guards and the application termination boundary. This establishes correctness under delayed work, not a measured stop-to-visible improvement. Folder migration and history reprocessing wait for preparation; at most eight recordings may await it, after which a visible error asks the user to retry. Cancel still invalidates a warm engine; cancellation during inference deliberately terminates it to avoid stale results. History transcription uses a separate helper, potentially overlapping live work. Device enumeration for a non-default microphone remains synchronous on stop.

## Release bundle packaging

Release builds strip debug and local symbols from the staged app and helper executables and keep only the arm64 slice of the staged Whisper framework before signing. Debug builds retain their symbols, and SwiftPM build products are not modified. On this machine, equivalent signed release bundles from source `9edc170` used 69,588 KiB before and 45,880 KiB after (`du -sk`); the sums of regular-file logical sizes were 71,205,911 and 46,926,935 bytes, respectively. Models are stored outside the bundle. Allocation varies by filesystem.

## Reproduction and limits

Measure allocated bundle and selected model storage separately. With each app idle and its root PID known, run `scripts/perf/process-sample.py --pid <PID> --seconds 60 --interval 5 --idle-confirmed`; verify idle state and look for helpers outside the process tree yourself. For dictation, use the same fixed playback, microphone, target, and sentence order, and record every transcript and failed trial. Record model, shortcut, residency, power source, sampling method, and whether model and settings match before interpreting differences.
