# Aura-AMD: Local AI Acceleration Control Room

## Project Overview

Aura-AMD is a fully localized, hardware-accelerated AI document analysis and generation platform built for the 17th Unisys Innovation Program (UIP 2026). It is designed to run complex Large Language Models (LLMs) directly on consumer hardware, bridging the gap between high-performance AI and data privacy.

## Why It Is Necessary

In the current enterprise and consumer landscape, relying on cloud-based AI presents several critical challenges:

1. **Data Privacy and Security:** Sending sensitive documents, financial records, or internal communications to external APIs poses significant security risks and compliance violations.
2. **High Latency:** Cloud inference is dependent on network stability and server load, leading to delayed responses.
3. **Hardware Underutilization:** Modern laptops possess powerful dedicated graphics cards (specifically AMD Radeon and NVIDIA RTX series) that remain completely idle during cloud AI operations.
4. **Deployment Friction:** Setting up local AI typically requires deep technical knowledge of Python virtual environments, CUDA drivers, and package managers, making it inaccessible to the average user.

## Key Benefits

Aura-AMD solves these issues through a zero-friction, highly optimized architecture:

* **Zero-Install Portable Bootstrap:** The application requires no pre-installed languages. It dynamically downloads portable, sandboxed versions of Go, Node.js, and Python, leaving the host operating system completely untouched.
* **Universal Hardware Acceleration:** Utilizing the DirectML execution provider via ONNX Runtime, the system natively accelerates inference on both AMD and NVIDIA GPUs, defaulting to CPU execution only if a dedicated GPU is absent.
* **Ultra-Low RAM Consumption:** By compiling the Go backend into a native binary and statically exporting the Next.js frontend, the system drastically reduces idle memory footprint compared to standard development environments.
* **Offline Reliability:** Once the initial model sync is complete, the entire Retrieval-Augmented Generation (RAG) pipeline—including the INT8 Quantized Phi-2 model and FAISS vector database—runs 100 percent locally and offline.

## User Usage Flow

The deployment process has been designed to be as simple as opening a standard desktop application.

### Prerequisites

* Windows 10 or 11 (DirectX 12 support required for DirectML acceleration).
* An active internet connection (only required for the first run to sync models and runtimes).

### Execution Steps

1. **Clone or Download the Repository:** Extract the project files to your desired folder.
2. **Run the Application:** Simply double-click the `start.bat` file located in the root directory.
3. **Access the Dashboard:** Once the terminal confirms the system is active, open your web browser and navigate to `http://localhost:3000`.
4. **Shutdown:** Press `Ctrl+C` in the terminal to trigger the automated garbage collection, which safely closes all background processes and releases system ports.

### What Happens Under the Hood?

When the application is launched for the first time, the background script performs the following automated sequence:

1. **Environment Resolution:** Detects missing runtimes and downloads portable Node.js, Go, and Python to a hidden `.runtimes` folder.
2. **Asset Synchronization:** Fetches the required 2.7GB INT8 ONNX model directly from Hugging Face into the local directory.
3. **Compilation:** Compiles the Go API into a lightweight binary and builds the Next.js frontend into a static production export.
4. **Hardware Allocation:** Boots the background Python engine, loads the AI model directly into the dedicated GPU's VRAM, and links it to the Go backend via persistent inter-process communication (IPC) for instant chat responses.

## Technical Stack

* **Backend System:** Go (Compiled Binary)
* **Machine Learning Engine:** Python 3.12 (ONNX Runtime, LangChain)
* **Models:** Phi-2 (INT8 Quantized, 2.7GB) for text generation, all-MiniLM-L6-v2 for document embedding.
* **Vector Storage:** FAISS and SQLite.
* **Frontend Interface:** Next.js (Static Export), React.

## Team Members

* **[Peeyush](https://github.com/breadOnLaptop):** Lead Developer & Architect and Backend & Systems
* **[Aditya](https://github.com/adityaMachal):** ML & Optimization
* **[Kartikeya](https://github.com/Bharadwaj-Karthikeya):** Frontend and UI Design Manager
