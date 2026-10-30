# Performance

Measured on an Apple M1 Max (64 GB), macOS 27.0.1, with the locally signed release app installed at `~/Applications/LightTTS.app`. A process-launch harness measured from spawning the executable until a marker written immediately after status-item construction. The first launch after rebuilding/reinstalling took **392.5 ms**. A later four-run sequence measured **368.6, 133.5, 123.4, and 114.0 ms**. These are single-machine observations with other applications running, not controlled cold-cache measurements. The first samples exceed the requested 200 ms target; the later warm samples meet it. Inference frameworks remain linked into the app process, and moving them to an on-demand helper is still a candidate for reducing cold launch.

Five seconds after the last launch, `ps` reported **0.0% CPU and 54,016 KiB RSS**. The selected model had not been loaded. The app reported Accessibility and Input Monitoring granted, microphone authorization `authorized`, and an active event tap after both release and debug rebuilds. The installed app's designated requirement remained the same certificate and bundle identifier across those builds. No renewed permission prompt was observed during the checks.

For end-to-end verification, a debug app used `LIGHTTTS_TEST_AUDIO` to feed a `say`-generated WAV without starting the microphone. A test-only HID event triggered the normal Option-Space shortcut, the recording popup was observed, and a second event stopped recording. Both Whisper tiny.en and Parakeet v3 inserted “This is a local speech recognition test.” into TextEdit; AppleScript read the text back. Earlier live speaker-to-microphone tests produced text with both engines but misrecognized the final word. Actual capture latency, largest-model memory, a controlled cold-launch distribution, and quit-during-download resume after process termination remain unmeasured.


On a later release build, readiness was redefined to require both catalog availability and a successfully installed hotkey. Five sequential launches, with tracing enabled and other apps running, reached that marker in **481.8, 235.5, 235.3, 696.5, and 523.5 ms**. These are not controlled cold-cache samples; none met 200 ms. Trace points cover entry to `main`, AppKit initialization, status-item creation, catalog availability and hotkey installation. Heavy inference dependencies remain directly linked, so the requested on-demand helper and cold-launch target remain outstanding.

## 2026-10-30 investigation (incomplete)

On the same M1 Max, an already-running SuperWhisper process with unknown model and prior activity showed an 88 MB physical footprint (`footprint`), and `ps` showed 215,712 KiB RSS and 2.2% CPU at approximately 22 seconds of process lifetime. It exited during the attempted `top -l 30 -s 2` collection, so these are neither five-minute idle measurements nor controlled comparisons. Other build and app processes were active. Do not interpret them as a head-to-head result.

| Metric / state | LightTTS main | LightTTS changes | SuperWhisper |
| --- | --- | --- | --- |
| Physical footprint, five-minute idle | Not measured | Not measured | Not measured |
| CPU, power, idle wakeups, five-minute idle | Not measured | Not measured | Not measured |
| Recording and transcription footprint / CPU / power | Not measured | Not measured | Not measured |
| Footprint after transcription and idle timeout | Not measured | Not measured | Not measured |
| Launch to status item | Not measured in this run | Not measured | Not measured |
| Hotkey to popup | Not measured | Not measured | Not measured |
| Stop to paste, same spoken utterance and model class | Not measured | Not measured | Not measured |

The current changes warm the selected model at recording start, release it after a configurable idle interval (`modelIdleTimeoutSeconds`, default 300 seconds, with timer tolerance), and dispose of hidden popup and menu view trees. Whisper GPU use was already enabled on main. This does not establish a performance win: controlled live audio benchmarks, wakeup/energy measurements, VAD, weight mapping and lazy inference framework loading remain outstanding. A detached model load already in progress may finish after cancellation before its memory can be reclaimed.

A separate release-build fixture run used an 8.5-second `say`-generated WAV fed directly to the test capture path with Whisper tiny.en and a two-second timeout. The footprint was 131 MB five seconds into capture and 146 MB at 20 seconds after launch; completion and post-unload were not established before the process was stopped. These observations do not measure live microphone capture, paste latency, or memory reclamation.

A second fixture run on the final release build completed transcription (136,136 samples). At 35 seconds after launch, its footprint was 146 MB and `ps` reported 0.0% CPU and 198,752 KiB RSS. The two-second timeout was configured for this test, but the measurement does not demonstrate a return to the original footprint. The optional Whisper Core ML encoder was absent; the log reported Metal initialization.

### Follow-up residency inspection

`otool -L` on the PR release executable shows direct dependencies on `whisper.framework`, Core ML, Accelerate, AVFoundation and SwiftUI. FluidAudio is compiled into the executable; this branch does not contain sherpa-onnx. Thus the inference dependencies are not isolated from launch, and releasing a model does not unload these frameworks or necessarily release their contexts.

An independently running installed LightTTS process with unknown build, settings and prior activity (over two hours old) showed 142 MB physical footprint in `footprint -j`: 89 MB untagged dirty memory, 34 MB malloc small and 2.8 MB graphics. `vmmap --summary` and `heap` corroborated the footprint; the latter identified many non-object allocations but did not attribute the largest allocations to a model. `leaks` reported that the process was not debuggable, limiting its inspection. This is diagnostic context only, not a measurement of this PR or a matched comparison.

A new configuration switch releases the engine as soon as transcription completes when disabled; when enabled (the default), the existing five-minute inactivity timer remains. Unload requests allocator pressure relief, but a cancelled in-flight model load or inference can retain its resources until it finishes. Neither the target footprint nor the other requested comparison rows have been verified for this change.

On the follow-up signed release build, a separate generated-WAV test process with retention disabled showed 146 MB physical footprint and 0.0% CPU at 25 seconds. `DYLD_PRINT_LIBRARIES` confirmed Whisper, Metal and Core ML loaded; Whisper initialized Metal. The process was terminated without an observed completion marker (stdout was redirected), so this sample cannot establish post-transcription release or live capture performance. It is not comparable to the 88 MB SuperWhisper observation above.
