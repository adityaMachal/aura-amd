# 🤖 Aura-AMD: Local AI Acceleration Control Room

**Aura-AMD** is a high-performance, privacy-first document intelligence platform. It leverages **INT8 Quantization** and **DirectML/CUDA** hardware acceleration to provide real-time RAG (Retrieval-Augmented Generation) insights directly on your local machine—no cloud API required.

## 🚀 One-Command Setup

We have automated the entire environment configuration, model synchronization, and service orchestration into a single PowerShell script.

### 1. Configure Environment

Before running the stack, set up your local environment variables:

1. **Create `.env**`: Copy the provided example file.
```powershell
cp .env.example .env

```


2. **Edit `.env**`: Open the file and ensure the `NEXT_PUBLIC_API_BASE` is set to your local Go backend.
```text
NEXT_PUBLIC_API_BASE=http://localhost:8080

```



### 2. Run the Automation Script

Open a PowerShell terminal in the root directory and run:

```powershell
.\startup.ps1

```

**What this script does for you:**

* **Frontend**: Automatically runs `npm install` if `node_modules` are missing.
* **ML-Engine**: Creates a Python `.venv`, upgrades pip, and installs all requirements.
* **Model Sync**: Detects if the **2.7GB INT8** model files exist; if not, it pulls them directly from our public Hugging Face repository.
* **Parallel Launch**: Starts the Go Backend, Next.js Frontend, and Python ML environment in parallel background jobs.

---

## 🛠️ Technical Architecture

| Component | Technology | Responsibility |
| --- | --- | --- |
| **Frontend** | Next.js (Tailwind CSS) | Real-time Dashboard with "Focus Mode" expanded chat. |
| **Backend** | Go (Gin Framework) | High-concurrency API gateway and hardware spec provider. |
| **ML Engine** | Python (Optimum + ONNX) | INT8 Quantized inference with dynamic DirectML/CUDA fallback. |
| **Database** | SQLite + FAISS | Local persistent chat history and vector document storage. |

---

## 👥 The Team

* **Peeyush** ([@breadOnLaptop](https://github.com/breadOnLaptop)) — *Lead Developer & Architect*
* **Aditya** ([@adityaMachal](https://github.com/adityaMachal)) — *Backend & Systems*
* **Karthikeya** ([@Bharadwaj-Karthikeya](https://github.com/Bharadwaj-Karthikeya)) — *ML & Optimization*

---

## 🧹 Garbage Collection

To stop all services and clear the assigned ports (`3000` and `8080`), simply press **`Ctrl+C`** in the PowerShell window. The script will trigger an automated cleanup of all background jobs and processes.

---
