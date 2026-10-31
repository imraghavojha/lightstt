# LightTTS

LightTTS is a macOS menu-bar speech-to-text app. It records speech, transcribes it locally or through a cloud provider, and inserts text into the focused app.

Features include configurable shortcuts and push-to-talk, audio input and output settings, a transcription library, model downloads and imports, and an optional local fallback for cloud transcription.

Requires Apple Silicon, macOS 14.2 or later, Swift 6, and Xcode command-line tools.

```sh
scripts/setup-signing.sh
scripts/install.sh
```

The signing setup requires the original LightTTS signing keychain; creating a new certificate would change the app identity. `scripts/build-app.sh` builds a signed app in `build/` without installing it. `scripts/check.sh` runs the local checks. `scripts/e2e-dictation.sh` exercises the installed app through a speaker and microphone when the required permissions are already granted.

Grant Microphone, Accessibility, and Input Monitoring permissions when prompted. The default shortcut is Option-Space. Apple Speech may require a system asset download and macOS 26 or later.

Local engines include Whisper, Parakeet, Canary, sherpa-onnx models, and Apple Speech. Cloud options include Groq, Gemini, ElevenLabs, and OpenAI-compatible endpoints. Cloud audio is sent to the selected provider; API keys are stored in Keychain. See the [model catalog schema](docs/models-schema.md).

The SwiftUI menu-bar app handles recording, settings, and text insertion. A separate helper process runs inference; LightTTSCore handles model storage and downloads. The CLI provides model and transcription commands.

## Performance

See [performance measurements](docs/perf.md) for the tested build, model, methods, and limits. The app bundle, downloaded models, and inference helper all contribute to resource use; measurements depend on the selected model and workload.
