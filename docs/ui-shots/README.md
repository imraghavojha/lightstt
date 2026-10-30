# Settings visual comparisons

The `settings-*` images show LightTTS at 2× in both appearances and presentations. Library images use synthetic entries supplied by `--ui-fixture`; fixture history is stored separately from the user's history. Detail captures use the synthetic WAV and synthetic metadata; no audio is played during capture. The empty Models host is intentional and will be filled by the models work.

The `ref-settings-*` images are reference-only Superwhisper captures. The History references are limited to a header or an empty search result to avoid including personal transcripts. Superwhisper presents its settings as a window, so the same window references inform both LightTTS presentations.

## Permission-free audio test

Set `LIGHTTTS_TEST_AUDIO` to a WAV file before launching the app. In this mode the file is resampled to 16 kHz mono and fed at real-time speed through the transcription pipeline. The app does not access the microphone, install global input monitors, play cues, control media players, or paste into another application. Test history is stored in the temporary directory, and the resulting text is written to the app's `testTranscript` preference. Post a distributed notification named `com.lighttts.test.toggle.<bundle identifier>` to start and stop the recording. The fake media lifecycle and audio filters can also be checked with `scripts/test-audio-processing.sh`.
