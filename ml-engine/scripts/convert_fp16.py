import onnx
from onnxconverter_common import float16
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ONNX_DIR = ROOT / "model" / "onnx"

fp32_model = ONNX_DIR / "model.onnx"
fp16_model = ONNX_DIR / "model-fp16.onnx"

print("Loading FP32 ONNX model...")
model = onnx.load(fp32_model, load_external_data=True)

print("Converting to FP16...")

model_fp16 = float16.convert_float_to_float16(
    model,
    keep_io_types=True,
    disable_shape_infer=True  # ✅ CRITICAL FIX
)

print("Saving FP16 ONNX model...")

onnx.save(
    model_fp16,
    fp16_model,
    save_as_external_data=True,
    all_tensors_to_one_file=True,
    location="model-fp16.onnx.data"
)

print("FP16 conversion completed.")