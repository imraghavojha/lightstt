On 2026-10-30, on an Apple M1 Max (64 GB), macOS 27.0.1, with other builds running, we built and installed revision `06e9474` as a signed release with the existing identity. Each app was freshly launched and allowed two minutes to settle; `footprint` measured physical footprint and 30 two-second `top` intervals after the initial sample were averaged. LightTTS launch was timed from process spawn to its status-item trace. For transcription, a `say`-generated 16 kHz mono WAV was fed through `LIGHTTTS_TEST_AUDIO` using Whisper tiny.en; a separate run pasted into a local test text field. Footprint sampling included the app and helper approximately every two seconds. SuperWhisper exited or relaunched during all three settling attempts, so no comparable idle sample or unattended transcription was established. Values are single-run observations under load.

| Metric | LightTTS | SuperWhisper |
| --- | --- | --- |
| Physical footprint after 2 min idle | 13 MB | N/A: three interrupted attempts |
| Idle CPU, energy impact, wakeups/s (60 s mean) | 0.0%, 0.0, 0.0 | N/A: three interrupted attempts |
| Launch to menu-bar item | 199 ms | N/A: item timing not observed |
| Stop to paste | 140 ms; expected text observed | N/A: transcription not established unattended |
| Peak footprint during transcription | N/A: sampling did not isolate processing; 156 MB app + helper observed around completion | N/A |
| Footprint 2.5 min after transcription | 18 MB; helper exited | N/A |
