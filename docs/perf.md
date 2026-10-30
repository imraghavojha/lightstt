# Performance

The status item is created synchronously without loading an inference model. Audio capture and inference are inactive until invoked; a loaded engine is retained between recordings. Launch time, idle CPU, and memory have not yet been measured. The targets (<200 ms to status item and near-zero idle CPU) are therefore not verified.

On an Apple M1 Max, both engines transcribed a short synthesized WAV correctly in a debug CLI smoke test. These are functional observations, not latency benchmarks. The release bundle built and its process launched, but status-item timing, idle measurements, and microphone-to-paste testing remain outstanding.
