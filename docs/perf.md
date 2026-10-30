On an Apple M1 Max (64 GB) running macOS 27.0.1, release builds were measured under load using footprint and top after two minutes idle and a synthetic 16 kHz WAV transcription with Whisper tiny.en.

| Metric | LightTTS | SuperWhisper |
| --- | --- | --- |
| Physical footprint after 2 min idle | 13 MB | N/A: three interrupted attempts |
| Idle CPU, energy impact, wakeups/s (60 s mean) | 0.0%, 0.0, 0.0 | N/A: three interrupted attempts |
| Launch to menu-bar item | 199 ms | N/A: item timing not observed |
| Stop to paste | 140 ms; expected text observed | N/A: transcription not established unattended |
| Peak footprint during transcription | N/A: sampling did not isolate processing; 156 MB app + helper observed around completion | N/A |
| Footprint 2.5 min after transcription | 18 MB; helper exited | N/A |
