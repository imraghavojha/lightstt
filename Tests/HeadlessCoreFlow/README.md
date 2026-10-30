# Headless core checks

Run `scripts/check.sh` on macOS. It generates speech with `say`, converts it to
16 kHz mono, exercises the real file reader and fixture capture, and deletes all
fixtures on exit. It runs the existing audio processing and fake media-controller
checks. When `~/Library/Application Support/LightTTS/Models/whisper-tiny.en` exists,
it builds and runs the real helper, primes inference, verifies the full sentence
and rejects bracketed annotations. The default warm latency limit is 400 ms;
`LIGHTTTS_TEST_MAX_LATENCY_MS` can override it for other hardware. No model is
downloaded by this script. A first build may take longer than a warm run.

Coverage gaps in this base revision, reported as skips rather than simulated tests:

- `AppController.swift:234`: shortcut transitions and cancellation are coupled to
  the controller and UI; extract an injectable state machine for toggle and PTT.
- `AppController.swift:317`: raw samples proceed to inference without a pure
  classifier for no buffers, digital silence, short input and normal input.
- `FocusTarget.swift:50` and `AppController.swift:358`: no injectable target
  classification or clipboard fallback for secure and non-editable fields, nor
  clipboard change-count restoration policy. Extract these decisions and effects.
- `AudioSettings.swift:100`: output volume restore uses private hardware access;
  extract an injectable volume session, including quantization and user changes.

The existing `TextInputPolicy` checks exercise input dispatch and copy settings;
they do not establish the missing secure-field and clipboard behavior.
