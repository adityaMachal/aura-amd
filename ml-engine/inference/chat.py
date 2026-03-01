import sys
import json
import os
import sqlite3
import warnings
import logging
import io
from contextlib import redirect_stdout, redirect_stderr

from langchain_huggingface import HuggingFaceEmbeddings # type: ignore
from langchain_community.vectorstores import FAISS # type: ignore
from transformers import AutoTokenizer # type: ignore
from optimum.onnxruntime import ORTModelForCausalLM # type: ignore
import onnxruntime as ort # type: ignore

logging.getLogger("transformers").setLevel(logging.ERROR)
logging.getLogger("optimum").setLevel(logging.ERROR)
os.environ['TOKENIZERS_PARALLELISM'] = 'false'
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
warnings.filterwarnings("ignore")

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "aura_store.db")

def log_chat(task_id, query, answer):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("INSERT INTO chats (task_id, role, content) VALUES (?, ?, ?)", (task_id, "user", query))
    c.execute("INSERT INTO chats (task_id, role, content) VALUES (?, ?, ?)", (task_id, "assistant", answer))
    conn.commit()
    conn.close()

def get_chat_history(task_id, limit=4):
    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("SELECT role, content FROM chats WHERE task_id = ? ORDER BY id DESC LIMIT ?", (task_id, limit))
        rows = c.fetchall()
        conn.close()
        history_text = ""
        for role, content in reversed(rows):
            if role == "user":
                history_text += f"User: {content}\n"
            else:
                history_text += f"Assistant: {content}\n"
        return history_text
    except sqlite3.OperationalError:
        return ""

def retrieve_context(task_id, query):
    faiss_path = os.path.join(os.path.dirname(__file__), "..", "..", "vector_stores", task_id)
    if not os.path.exists(faiss_path):
        return "", []
    embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
    vector_db = FAISS.load_local(faiss_path, embeddings, allow_dangerous_deserialization=True)
    docs = vector_db.similarity_search(query, k=3)
    context_text = "\n".join([doc.page_content for doc in docs])
    sources = list(set([doc.metadata.get("page", 0) + 1 for doc in docs]))
    return context_text, sources

# FIX: Added model and tokenizer to the function parameters
def generate_response(task_id, query, model, tokenizer):
    context, sources = retrieve_context(task_id, query)
    chat_history = get_chat_history(task_id)

    # Updated Phi-2 specific prompt format
    prompt = f"""Instruct: You are a direct, concise document extraction AI. Answer the question using ONLY the provided Document Context. Do not ask follow-up questions.

Document Context:
{context}

Chat History:
{chat_history}

Question: {query}
Output:"""

    try:
        inputs = tokenizer(prompt, return_tensors="pt").to(model.device)

        generate_ids = model.generate(
            **inputs,
            max_new_tokens=150,
            temperature=0.1,        # Lowered to 0.1 for strict, factual answers
            do_sample=True,
            top_p=0.85,
            repetition_penalty=1.1,
            pad_token_id=tokenizer.eos_token_id,
            eos_token_id=tokenizer.eos_token_id
        )

        answer = tokenizer.decode(generate_ids[0][inputs.input_ids.shape[-1]:], skip_special_tokens=True).strip()

        # FIX: Hard-cutoff hallucinated conversation continuations
        stop_words = ["User:", "Question:", "Instruct:", "Assistant:"]
        for word in stop_words:
            if word in answer:
                answer = answer.split(word)[0].strip()

        log_chat(task_id, query, answer)
        return {"answer": answer, "sources": sources}
    except Exception as e:
        return {"answer": f"Inference Error: {str(e)}", "sources": []}


if __name__ == "__main__":
    current_dir = os.path.dirname(os.path.abspath(__file__))
    model_dir = os.path.join(current_dir, "..", "model", "onnx")

    available_providers = ort.get_available_providers()
    selected_provider = 'CPUExecutionProvider'
    provider_options = {}
    model = None

    tokenizer = AutoTokenizer.from_pretrained(model_dir)

    if 'DmlExecutionProvider' in available_providers:
        selected_provider = 'DmlExecutionProvider'

        # ATTEMPT 1: Target Dedicated Laptop GPU (Device 1)
        try:
            provider_options = {"device_id": 1}
            model = ORTModelForCausalLM.from_pretrained(
                model_dir,
                file_name="model-int8.onnx",
                provider=selected_provider,
                provider_options=provider_options,
                use_cache=True,
                use_io_binding=True
            )
        except Exception:
            # ATTEMPT 2: Fallback to Integrated Graphics (Device 0)
            model = None

    # If model is still None (either DML fallback triggered, or DML isn't installed)
    if model is None:
        if 'DmlExecutionProvider' in available_providers:
            provider_options = {"device_id": 0}

        model = ORTModelForCausalLM.from_pretrained(
            model_dir,
            file_name="model-int8.onnx",
            provider=selected_provider,
            provider_options=provider_options,
            use_cache=True,
            use_io_binding=True
        )

    print("READY", flush=True)

    # 2. CONTINUOUS LISTENING LOOP
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            data = json.loads(line)
            task_id = data.get("task_id")
            query = data.get("query")

            if not task_id or not query:
                continue

            trap = io.StringIO()
            with redirect_stdout(trap), redirect_stderr(trap):
                # FIX: Passing the global model and tokenizer to the function
                result = generate_response(task_id, query, model, tokenizer)

            print(json.dumps(result), flush=True)

        except Exception as e:
            print(json.dumps({"answer": f"System Error: {str(e)}", "sources": []}), flush=True)
