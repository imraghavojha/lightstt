# LightTTS

LightTTS is a macOS menu-bar speech-to-text app. It records speech, transcribes it locally or through a cloud provider, and inserts text into the focused app.

Features include configurable shortcuts and push-to-talk, audio input and output settings, a transcription library, model downloads and imports, and an optional local fallback for cloud transcription.

Requires Apple Silicon, macOS 14.2 or later, Swift 6, and Xcode command-line tools.

```sh
scripts/setup-signing.sh
scripts/build-app.sh
open ~/Applications/LightTTS.app
```

Grant Microphone, Accessibility, and Input Monitoring permissions when prompted. The default shortcut is Option-Space. Apple Speech may require a system asset download and macOS 26 or later.

Local engines include Whisper, Parakeet, Canary, sherpa-onnx models, and Apple Speech. Cloud options include Groq, Gemini, ElevenLabs, and OpenAI-compatible endpoints. Cloud audio is sent to the selected provider; API keys are stored in Keychain. See the [model catalog schema](docs/models-schema.md).

The SwiftUI menu-bar app handles recording, settings, and text insertion. A separate helper process runs inference; LightTTSCore handles model storage and downloads. The CLI provides model and transcription commands.

## Performance

Measured on an Apple M1 Max with 64 GB RAM; see [method](docs/perf.md).

| Metric | LightTTS | SuperWhisper |
| --- | --- | --- |
| Physical footprint after 2 min idle | 13 MB | N/A: three interrupted attempts |
| Idle CPU, energy impact, wakeups/s (60 s mean) | 0.0%, 0.0, 0.0 | N/A: three interrupted attempts |
| Launch to menu-bar item | 199 ms | N/A: item timing not observed |
| Stop to paste | 140 ms; expected text observed | N/A: transcription not established unattended |
| Peak footprint during transcription | N/A: 156 MB app + helper observed around completion | N/A |
| Footprint 2.5 min after transcription | 18 MB; helper exited | N/A |
