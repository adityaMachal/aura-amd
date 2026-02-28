from optimum.onnxruntime import ORTModelForCausalLM
from transformers import AutoTokenizer
from pathlib import Path
import torch

ROOT = Path(__file__).resolve().parent.parent
MODEL_DIR = ROOT / "model" / "base"
ONNX_DIR = ROOT / "model" / "onnx"

ONNX_DIR.mkdir(parents=True, exist_ok=True)

print("Loading tokenizer...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)

print("Exporting Phi-2 to FP16 ONNX...")
model = ORTModelForCausalLM.from_pretrained(
    MODEL_DIR,
    export=True,
    provider="CPUExecutionProvider",
    dtype=torch.float16
)

model.save_pretrained(ONNX_DIR)
tokenizer.save_pretrained(ONNX_DIR)

print("FP16 ONNX export completed.")