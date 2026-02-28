from transformers import AutoTokenizer, AutoModelForCausalLM
from pathlib import Path

MODEL_ID = "microsoft/phi-2"
TARGET_DIR = Path(__file__).resolve().parent.parent / "model" / "base"

tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
model = AutoModelForCausalLM.from_pretrained(MODEL_ID)

tokenizer.save_pretrained(TARGET_DIR)
model.save_pretrained(TARGET_DIR)

print("Phi-2 model downloaded.")