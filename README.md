<img src="assets/icon.svg" width="64" height="64" alt="">

# LightTTS

A local macOS menu-bar speech-to-text app for Apple Silicon and macOS 14+. Build with Swift and the Xcode command-line tools:

```sh
scripts/build-app.sh
scripts/run.sh
```

Grant Microphone and Accessibility permissions, download a model in Models, then press Option-Space to start and stop dictation. Settings include push-to-talk and Right Option. The transcription is pasted into the previously focused application. The WAV harness is `swift run lighttts-cli whisper MODEL_FILE AUDIO_FILE` or `swift run lighttts-cli parakeet-v2 MODEL_DIRECTORY AUDIO_FILE` (also `parakeet-v3`). Model data is local to your Mac; downloads come from the model providers. See [catalog schema](docs/models-schema.md) and [performance notes](docs/perf.md).

This is an in-progress implementation. The full microphone/hotkey/paste flow has not yet been verified end to end. Download progress, cancellation and resumable Whisper downloads are not implemented, and the package currently uses Swift 5 language mode with a Swift 6 toolchain. See the pull request for verification and remaining work.
