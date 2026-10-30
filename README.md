<img src="assets/icon.svg" width="64" height="64" alt="">

# LightTTS

A local macOS menu-bar speech-to-text app for Apple Silicon and macOS 14+. Build with Swift and the Xcode command-line tools:

```sh
scripts/build-app.sh
scripts/run.sh
```

The build uses an ad-hoc signature by default; set `LIGHTTTS_CODESIGN_IDENTITY` to a valid signing identity for stable permissions across rebuilds. Grant Microphone, Accessibility and Input Monitoring permissions, download a model in Models, then press Option-Space to start and stop dictation. Settings include push-to-talk and Right Option. The transcription is inserted into the previously focused field using Accessibility. If the field does not support text insertion, LightTTS reports an error and leaves the clipboard unchanged. The WAV harness is `swift run lighttts-cli whisper MODEL_FILE AUDIO_FILE` or `swift run lighttts-cli parakeet-v2 MODEL_DIRECTORY AUDIO_FILE` (also `parakeet-v3`). Model data is local to your Mac; downloads come from the model providers. See [catalog schema](docs/models-schema.md) and [performance notes](docs/perf.md).

This is an in-progress implementation. A debug test harness can exercise hotkey, recording and insertion using a WAV fixture; live speaker-to-microphone capture has also been checked on the development Mac. Downloads show progress and support cancellation and resume. The package currently uses Swift 5 language mode with a Swift 6 toolchain. See the pull request for verification and remaining work.

For development, set `LIGHTTTS_BUILD_CONFIGURATION=debug` when running the build script. A debug app launched with `LIGHTTTS_TEST_WAV` pointing to a 16 kHz speech WAV and `LIGHTTTS_TEST_MODEL` set to a catalog ID can be driven using `swift scripts/test-trigger.swift <pid> hid` twice; `toggle` exercises the same handler without a synthetic key. The debug test script activates TextEdit. These notification triggers and WAV substitution are excluded from release builds.

Run `scripts/setup-signing.sh` once to create and trust the local code-signing identity in your login keychain. Subsequent builds sign with that identity when available and update `~/Applications/LightTTS.app` in place; the signing certificate and bundle identifier define a stable code requirement, provided the identity remains accessible to codesign. If no identity is available, builds fall back to ad-hoc signing and macOS may ask for permissions again. The setup imports the key with an ACL for `codesign`; macOS may still require an initial keychain authorization. Partition-list setup requires a uniquely labeled private key and the login keychain password.

For debug builds, `LIGHTTTS_TEST_AUDIO` selects a WAV input without starting the microphone, and the debug-only `lighttts://toggle` URL triggers the same shortcut handler. The app requests missing microphone, Accessibility and Input Monitoring permissions during its first onboarding pass; previously granted permissions are not requested again.
