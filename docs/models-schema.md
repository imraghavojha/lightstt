# Model catalog

`Sources/LightTTSCore/Resources/models.json` is a JSON array. Each entry has a unique, filesystem-safe `id`, a display `name`, and an `engine` (`whisper` or `parakeet`). Whisper entries provide a direct `url` to a whisper.cpp GGML model. Parakeet entries provide `version` (`v2` or `v3`); FluidAudio manages the associated Core ML files. IDs also determine their paths beneath `~/Library/Application Support/LightTTS/Models` and must remain stable across catalog updates.
