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

logging.getLogger("transformers").setLevel(logging.ERROR)
logging.getLogger("optimum").setLevel(logging.ERROR)
os.environ['TOKENIZERS_PARALLELISM'] = 'false'
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
warnings.filterwarnings("ignore")

# Moved storage up to the root folder (aura-amd/)
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
    # Moved vector store up to the root folder (aura-amd/vector_stores)
    faiss_path = os.path.join(os.path.dirname(__file__), "..", "..", "vector_stores", task_id)
    if not os.path.exists(faiss_path):
        return "", []

    embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
    vector_db = FAISS.load_local(faiss_path, embeddings, allow_dangerous_deserialization=True)

    docs = vector_db.similarity_search(query, k=3)
    context_text = "\n".join([doc.page_content for doc in docs])
    sources = list(set([doc.metadata.get("page", 0) + 1 for doc in docs]))

    return context_text, sources

def generate_response(task_id, query):
    current_dir = os.path.dirname(os.path.abspath(__file__))
    model_dir = os.path.join(current_dir, "..", "model", "onnx")
    model_file = os.path.join(model_dir, "model-int8.onnx")

    context, sources = retrieve_context(task_id, query)
    chat_history = get_chat_history(task_id)

    prompt = f"""System: You are an expert document extraction AI. Answer the user's prompt directly using ONLY the provided Document Context. Do not use conversational filler. If the user refers to previous questions, use the Chat History.

Document Context:
{context}

Chat History:
{chat_history}

User: {query}
Answer:"""

    if not os.path.exists(model_file):
        return {"answer": f"Error: ONNX model not found at {model_file}", "sources": sources}

    try:
        from transformers import AutoTokenizer
        from optimum.onnxruntime import ORTModelForCausalLM
        import onnxruntime as ort

        available_providers = ort.get_available_providers()

        selected_provider = 'CPUExecutionProvider'
        if 'CUDAExecutionProvider' in available_providers:
            selected_provider = 'CUDAExecutionProvider'
        elif 'DmlExecutionProvider' in available_providers:
            selected_provider = 'DmlExecutionProvider'

        tokenizer = AutoTokenizer.from_pretrained(model_dir)
        model = ORTModelForCausalLM.from_pretrained(
            model_dir,
            file_name="model-int8.onnx",
            provider=selected_provider
        )

        inputs = tokenizer(prompt, return_tensors="pt")

        generate_ids = model.generate(
            **inputs,
            max_new_tokens=150,
            temperature=0.3,
            do_sample=True,
            top_p=0.85,
            repetition_penalty=1.2,
            no_repeat_ngram_size=3,
            pad_token_id=tokenizer.eos_token_id
        )

        answer = tokenizer.decode(generate_ids[0][inputs.input_ids.shape[-1]:], skip_special_tokens=True).strip()

        log_chat(task_id, query, answer)

        return {"answer": answer, "sources": sources}

    except Exception as e:
        return {"answer": f"Inference Error: {str(e)}", "sources": []}

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(json.dumps({"answer": "Error: Missing arguments.", "sources": []}))
        sys.exit(1)

    task_id = sys.argv[1]
    query = sys.argv[2]

    trap = io.StringIO()
    with redirect_stdout(trap), redirect_stderr(trap):
        result = generate_response(task_id, query)

    print(json.dumps(result), file=sys.__stdout__)
    sys.__stdout__.flush()
