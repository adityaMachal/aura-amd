import onnxruntime as ort
from transformers import AutoTokenizer
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "model" / "onnx"

tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)

providers = ["DmlExecutionProvider", "CPUExecutionProvider"]

try:
    session = ort.InferenceSession(
        str(MODEL_DIR / "model.onnx"),
        providers=providers
    )
    print("Using provider:", session.get_providers()[0])
except Exception:
    print("DirectML failed, falling back to CPU.")
    session = ort.InferenceSession(
        str(MODEL_DIR / "model.onnx"),
        providers=["CPUExecutionProvider"]
    )
    print("Using provider: CPUExecutionProvider")

prompt = "DirectML fallback smoke test."
inputs = tokenizer(prompt, return_tensors="np")

input_ids = inputs["input_ids"]
attention_mask = inputs["attention_mask"]

batch_size, seq_len = input_ids.shape

# Phi-2 specifics
num_layers = 32
num_heads = 32
head_dim = 80

# Position IDs
position_ids = np.arange(seq_len, dtype=np.int64).reshape(1, -1)

# Empty KV cache
past_key_values = {}
for i in range(num_layers):
    past_key_values[f"past_key_values.{i}.key"] = np.zeros(
        (batch_size, num_heads, 0, head_dim), dtype=np.float32
    )
    past_key_values[f"past_key_values.{i}.value"] = np.zeros(
        (batch_size, num_heads, 0, head_dim), dtype=np.float32
    )

ort_inputs = {
    "input_ids": input_ids,
    "attention_mask": attention_mask,
    "position_ids": position_ids,
    **past_key_values,
}

session.run(None, ort_inputs)

print("Inference executed successfully.")