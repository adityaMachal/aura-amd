import sys
import json
import os
import sqlite3
import warnings
import logging

import torch # Required for hardware detection

from langchain_community.document_loaders import PyPDFLoader # type: ignore
from langchain_text_splitters import RecursiveCharacterTextSplitter # type: ignore
from langchain_huggingface import HuggingFaceEmbeddings # type: ignore
from langchain_community.vectorstores import FAISS # type: ignore

logging.getLogger("transformers").setLevel(logging.ERROR)
logging.getLogger("optimum").setLevel(logging.ERROR)
os.environ['TOKENIZERS_PARALLELISM'] = 'false'
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
warnings.filterwarnings("ignore")

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "aura_store.db")

def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS documents
                 (task_id TEXT PRIMARY KEY, file_path TEXT, chunk_count INTEGER)''')
    c.execute('''CREATE TABLE IF NOT EXISTS chats
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT, role TEXT, content TEXT)''')
    conn.commit()
    conn.close()

def process_document(task_id, file_path):
    try:
        init_db()

        loader = PyPDFLoader(file_path)
        documents = loader.load()

        text_splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)
        chunks = text_splitter.split_documents(documents)

        # 1. HARDWARE TARGETING: Check for native PyTorch CUDA (Nvidia) support
        device = "cuda" if torch.cuda.is_available() else "cpu"

        # 2. ACCELERATION: Pass the device and increase the batch size
        embeddings = HuggingFaceEmbeddings(
            model_name="all-MiniLM-L6-v2",
            model_kwargs={'device': device},
            encode_kwargs={'batch_size': 32} # Processes 32 chunks simultaneously instead of 1
        )

        vector_db = FAISS.from_documents(chunks, embeddings)

        faiss_path = os.path.join(os.path.dirname(__file__), "..", "..", "vector_stores", task_id)
        os.makedirs(faiss_path, exist_ok=True)
        vector_db.save_local(faiss_path)

        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute("INSERT OR REPLACE INTO documents (task_id, file_path, chunk_count) VALUES (?, ?, ?)",
                  (task_id, file_path, len(chunks)))
        conn.commit()
        conn.close()

        return {
            "summary": f"Document analyzed successfully. {len(chunks)} chunks embedded via {device.upper()} and logged.",
            "tokens_per_sec": 0
        }
    except Exception as e:
        return {"summary": f"Error: {str(e)}", "tokens_per_sec": 0}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)

    file_path = sys.argv[1]
    task_id = os.path.splitext(os.path.basename(file_path))[0]

    result = process_document(task_id, file_path)

    sys.stdout.flush()
    print(json.dumps(result))
