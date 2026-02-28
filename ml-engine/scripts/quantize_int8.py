from onnxruntime.quantization import quantize_dynamic, QuantType
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ONNX_DIR = ROOT / "model" / "onnx"

input_model = ONNX_DIR / "model.onnx"
output_model = ONNX_DIR / "model-int8.onnx"

quantize_dynamic(
    model_input=str(input_model),
    model_output=str(output_model),
    weight_type=QuantType.QInt8,
    use_external_data_format=True
)

print("INT8 quantization completed.")