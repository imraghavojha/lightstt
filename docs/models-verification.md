# Model verification

On macOS 27.0.1, Apple M1 Max, a 16 kHz mono WAV was generated with `say -o /tmp/t.aiff "..."` and `afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/t.aiff /tmp/t.wav`. The WAV contained the sentence “The quick brown fox jumps over the lazy dog. This is a speech recognition test.” It was read with `lighttts-cli transcribe MODEL_ID AUDIO_FILE`. The following models were installed with `lighttts-cli download MODEL_ID` or through the Models page and returned that sentence, allowing for case and punctuation:

- whisper.cpp: `whisper-tiny-q5_1`, `distil-small.en`, `distil-medium.en`, `distil-large-v3`, `distil-large-v3.5`, `distil-large-v2`.
- FluidAudio: `parakeet-v2`, `parakeet-v3`, `parakeet-redux`, `parakeet-ultra`, `parakeet-tdt-ctc-110m`, `canary-1b-v2`.
- sherpa-onnx: `moonshine-tiny`, `moonshine-base`, `sherpa-sense_voice`, `sherpa-paraformer`, `sherpa-zipformer`, `sherpa-whisper_onnx`, `sherpa-nemo_parakeet`, `sherpa-nemo_canary`.
- Apple Speech: `apple-speech`, using the current English locale and installed system assets.

`parakeet-ja` also transcribed a Japanese synthetic sentence. The Whisper medium download was started, canceled, and resumed in the app, and completed with its SHA-256 verified. `LIGHTTTS_TEST_ADHOC=1 scripts/build-app.sh` built and ad-hoc signed the app without updating the installed copy. The merged base’s `model-validation` checks for corrupt models and download cancellation/resume also passed. These are smoke tests of short synthetic audio, not accuracy or performance benchmarks. Other catalog variants share the tested runtime paths but have not each been transcribed individually.
