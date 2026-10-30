import Foundation
public enum SherpaModelFiles {
    public static func requiredFiles(_ type: String) throws -> [String] {
        switch type { case "moonshine": return ["preprocess.onnx", "encode.int8.onnx", "uncached_decode.int8.onnx", "cached_decode.int8.onnx", "tokens.txt"]; case "moonshine_v2": return ["encoder_model.ort", "decoder_model_merged.ort", "tokens.txt"]; case "qwen3": return ["conv_frontend.onnx", "encoder.int8.onnx", "decoder.int8.onnx", "tokenizer/vocab.json", "tokenizer/merges.txt", "tokenizer/tokenizer_config.json"]; case "sense_voice", "paraformer": return ["model.int8.onnx", "tokens.txt"]; case "zipformer": return ["encoder-epoch-99-avg-1.int8.onnx", "decoder-epoch-99-avg-1.int8.onnx", "joiner-epoch-99-avg-1.int8.onnx", "tokens.txt"]; case "whisper_onnx": return ["tiny.en-encoder.int8.onnx", "tiny.en-decoder.int8.onnx", "tiny.en-tokens.txt"]; case "nemo_parakeet": return ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]; case "nemo_canary": return ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"]; default: throw SpeechError.model("Unsupported sherpa model type") }
    }
}
