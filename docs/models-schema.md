# Model catalog

`Sources/LightTTSCore/Resources/models.json` is an array of models with a filesystem-safe `id`, `name`, `engine`, and optional `version`, `size`, `speed`, `accuracy`, and `languages`.

Whisper entries provide an HTTPS `url` and SHA-256. Sherpa entries provide a `version` and `files` with relative `path`, HTTPS `url`, `size`, and `sha256`. Parakeet and Canary entries select SDK model versions; Apple Speech assets are managed by macOS.

Custom models can be imported from compatible local files or directories, Hugging Face repositories, or URLs. Whisper URLs require a SHA-256; non-Whisper URLs can point to a JSON file manifest using the Sherpa file fields.
