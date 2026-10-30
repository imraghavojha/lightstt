<img src="assets/icon.svg" width="64" height="64" alt="">

# LightTTS

A local macOS menu-bar speech-to-text app for Apple Silicon and macOS 14+. Build with Swift and the Xcode command-line tools:

```sh
scripts/setup-signing.sh
scripts/build-app.sh
scripts/run.sh
```

Grant Microphone, Accessibility and Input Monitoring permissions, download a model in Models, then press Option-Space to start and stop dictation. Settings include push-to-talk and Right Option. The transcription is inserted into the previously focused field using Accessibility. If the field does not support text insertion, LightTTS reports an error and leaves the clipboard unchanged. The WAV harness is `swift run lighttts-cli whisper MODEL_FILE AUDIO_FILE` or `swift run lighttts-cli parakeet-v2 MODEL_DIRECTORY AUDIO_FILE` (also `parakeet-v3`). Model data is local to your Mac; downloads come from the model providers. See [catalog schema](docs/models-schema.md) and [performance notes](docs/perf.md).

This is an in-progress implementation. A debug test harness can exercise hotkey, recording and insertion using a WAV fixture; live speaker-to-microphone capture has also been checked on the development Mac. Downloads show progress and support cancellation and resume. The package currently uses Swift 5 language mode with a Swift 6 toolchain. See the pull request for verification and remaining work.

For development, set `LIGHTTTS_BUILD_CONFIGURATION=debug` when running the build script. A debug app launched with `LIGHTTTS_TEST_WAV` pointing to a 16 kHz speech WAV and `LIGHTTTS_TEST_MODEL` set to a catalog ID can be driven using `swift scripts/test-trigger.swift <pid> hid` twice; `toggle` exercises the same handler without a synthetic key. The debug test script activates TextEdit. These notification triggers and WAV substitution are excluded from release builds.

Run `scripts/setup-signing.sh` once to create the dedicated local development signing keychain. Builds use its identity and update `~/Applications/LightTTS.app` in place; the certificate and bundle identifier define a stable code requirement. The keychain uses a known local password and is intended only for development. Newly created keys are non-exportable and restricted to codesign; existing identities are left unchanged and may retain broader access.

Set `LIGHTTTS_TEST_AUDIO` to a WAV file to run a paced, permission-free transcription test: microphone input, global monitors, media controls, sound cues, and pasting are bypassed, and the resulting text is stored in the `testTranscript` preference. Post the distributed notification `com.lighttts.test.toggle.<bundle identifier>` to start or stop this test. Normal use requests missing microphone, Accessibility and Input Monitoring permissions during its first onboarding pass; previously granted permissions are not requested again.
