"use client";

import { useEffect, useMemo, useRef, useState } from "react";

type SystemStatusResponse = {
  status?: "processing" | "completed" | "error";
  summary?: string;
  tokens_per_sec?: number;
};

type ChatMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
  sources?: number[];
};

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? "";

function Toast({ message }: { message: string }) {
  return (
    <div className="toast">
      <span>{message}</span>
    </div>
  );
}

export default function Home() {
  const [info, setInfo] = useState<Record<string, string>>({});
  const [taskId, setTaskId] = useState<string | null>(null);
  const [status, setStatus] = useState<
    "idle" | "uploading" | "processing" | "completed" | "error"
  >("idle");
  const [summaryFull, setSummaryFull] = useState<string | null>(null);
  const [summaryTyped, setSummaryTyped] = useState("");
  const [tokensPerSec, setTokensPerSec] = useState<number | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [chatInput, setChatInput] = useState("");
  const [isChatting, setIsChatting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);
  const chatEndRef = useRef<HTMLDivElement | null>(null);
  const modalChatEndRef = useRef<HTMLDivElement | null>(null);

  // Auto-scroll to bottom of chat
  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
    modalChatEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, summaryTyped, isModalOpen]);

  // Fetch Hardware Specs
  useEffect(() => {
    const fetchInfo = async () => {
      try {
        const response = await fetch(`${API_BASE}/api/v1/system/info`, {
          cache: "no-store",
        });
        if (!response.ok) return;
        const data = (await response.json()) as Record<string, string>;
        setInfo(data ?? {});
      } catch (err) {
        return;
      }
    };
    fetchInfo();
  }, []);

  // Poll for Task Status
  useEffect(() => {
    if (!taskId) return;
    let isMounted = true;
    const interval = setInterval(async () => {
      try {
        const response = await fetch(
          `${API_BASE}/api/v1/analyze/status/${taskId}`,
          { cache: "no-store" }
        );
        if (!response.ok) return;
        const data = (await response.json()) as SystemStatusResponse;
        if (!isMounted) return;

        if (data.status === "completed") {
          setStatus("completed");
          setTokensPerSec(
            typeof data.tokens_per_sec === "number" ? data.tokens_per_sec : null
          );
          if (data.summary && !summaryFull) {
            setSummaryFull(data.summary);
          }
          clearInterval(interval);
        } else if (data.status === "error") {
          setStatus("error");
          clearInterval(interval);
        } else {
          setStatus("processing");
        }
      } catch (err) {
        return;
      }
    }, 2000);

    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, [taskId, summaryFull]);

  // Typing effect for summary
  useEffect(() => {
    if (!summaryFull) return;
    setSummaryTyped("");
    let index = 0;
    const interval = setInterval(() => {
      index += 1;
      setSummaryTyped(summaryFull.slice(0, index));
      if (index >= summaryFull.length) clearInterval(interval);
    }, 20);
    return () => clearInterval(interval);
  }, [summaryFull]);

  // Toast timeout
  useEffect(() => {
    if (!toast) return;
    const timeout = setTimeout(() => setToast(null), 2400);
    return () => clearTimeout(timeout);
  }, [toast]);

  const uploadDocument = async () => {
    const file = fileRef.current?.files?.[0];
    if (!file) return;
    setError(null);
    setStatus("uploading");
    setMessages([]);
    setSummaryFull(null);
    setSummaryTyped("");
    setTokensPerSec(null);
    try {
      const formData = new FormData();
      formData.append("file", file);
      const response = await fetch(`${API_BASE}/api/v1/analyze/upload`, {
        method: "POST",
        body: formData,
      });
      if (!response.ok) throw new Error("Upload failed");
      const data = (await response.json()) as { task_id?: string };
      setTaskId(data.task_id ?? null);
      setStatus("processing");
    } catch (err) {
      setStatus("error");
      setError("Upload failed. Check the API and try again.");
    }
  };

  const sendChat = async () => {
    if (!taskId || !chatInput.trim()) return;
    const question = chatInput.trim();
    setChatInput("");
    const userMessage: ChatMessage = {
      id: crypto.randomUUID(),
      role: "user",
      content: question,
    };
    setMessages((prev) => [...prev, userMessage]);
    setIsChatting(true);
    setError(null);

    try {
      const response = await fetch(`${API_BASE}/api/v1/analyze/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ task_id: taskId, query: question }),
      });
      if (!response.ok) throw new Error("Chat failed");
      const data = (await response.json()) as {
        answer?: string;
        sources?: number[];
      };
      const assistantMessage: ChatMessage = {
        id: crypto.randomUUID(),
        role: "assistant",
        content: data.answer ?? "No answer returned.",
        sources: data.sources ?? [],
      };
      setMessages((prev) => [...prev, assistantMessage]);
    } catch (err) {
      setError("Chat request failed. Try again.");
    } finally {
      setIsChatting(false);
    }
  };

  const purgeData = async () => {
    setError(null);
    const currentTask = taskId;
    setTaskId(null);
    setMessages([]);
    setSummaryFull(null);
    setSummaryTyped("");
    setTokensPerSec(null);
    setStatus("idle");
    try {
      if (currentTask) {
        await fetch(`${API_BASE}/api/v1/analyze/purge/${currentTask}`, {
          method: "DELETE",
        });
      }
      setToast("Local cache purged successfully.");
    } catch (err) {
      setError("Purge failed. Check the API and try again.");
    }
  };

  const infoEntries = useMemo(() => {
    const entries = Object.entries(info ?? {}).filter(
      ([, value]) => value !== null && value !== undefined && value !== ""
    );
    return entries.length ? entries : [["status", "Awaiting specs..."]];
  }, [info]);

  // Reusable Chat Rendering Logic
  const renderChatMessages = () => (
    <>
      {summaryFull && (
        <div className="chat-bubble assistant">
          <div className="text-sm text-slate-100">
            {summaryTyped}
            {summaryTyped.length < summaryFull.length && (
              <span className="typing-caret" />
            )}
          </div>
        </div>
      )}

      {messages.map((message) => (
        <div key={message.id} className={`chat-bubble ${message.role}`}>
          <p className="text-sm text-slate-100">{message.content}</p>
          {message.sources && message.sources.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-2 text-[11px] text-emerald-200">
              {message.sources.map((source) => (
                <span
                  key={`${message.id}-${source}`}
                  className="rounded-full border border-emerald-300/40 px-2 py-0.5"
                >
                  Reference: Found in Page {source}
                </span>
              ))}
            </div>
          )}
        </div>
      ))}
    </>
  );

  const renderChatInputBar = () => (
    <div className="border-t border-slate-800 pt-3">
      <div className="flex items-center gap-3">
        <input
          value={chatInput}
          onChange={(event) => setChatInput(event.target.value)}
          onKeyDown={(e) => e.key === "Enter" && sendChat()}
          placeholder="Ask about your document..."
          className="flex-1 rounded-full border border-slate-800 bg-slate-950/70 px-4 py-2 text-sm text-slate-200 outline-none focus:border-emerald-400"
        />
        <button
          onClick={sendChat}
          className="rounded-full bg-emerald-400/90 px-4 py-2 text-sm font-semibold text-slate-900 transition hover:bg-emerald-300"
        >
          Send
        </button>
      </div>
      <div className="mt-2 flex items-center justify-between text-xs text-slate-400">
        <span>{taskId ? `Task ${taskId}` : "Upload a document to begin"}</span>
        <span>{tokensPerSec ? `Speed: ${tokensPerSec} tok/s` : ""}</span>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-aura">
      <div className="grid-lines" />
      <div className="mx-auto flex min-h-screen max-w-7xl flex-col gap-8 px-6 py-10 lg:flex-row">
        <section className="flex-1 space-y-6">
          <header className="flex flex-col gap-3">
            <p className="text-xs uppercase tracking-[0.4em] text-slate-400">
              Aura-AMD Dashboard
            </p>
            <h1 className="text-4xl font-semibold text-white">
              Local AI Acceleration Control Room
            </h1>
            <p className="max-w-2xl text-sm text-slate-300">
              Push documents for analysis and chat with insights in real time.
            </p>
          </header>

          <div className="grid gap-6 lg:grid-cols-[1.2fr_1fr]">
            <div className="glass-card space-y-4">
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold text-white">
                  Document Hub
                </h2>
                <div
                  className={`h-10 w-10 rounded-full border border-slate-700 bg-slate-900/70 p-2 ${
                    status === "uploading" || status === "processing"
                      ? "animate-pulse"
                      : ""
                  }`}
                >
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    className="h-full w-full text-slate-200"
                  >
                    <path d="M7 3h6l4 4v14H7V3z" stroke="currentColor" strokeWidth="1.5" />
                    <path d="M13 3v5h5" stroke="currentColor" strokeWidth="1.5" />
                  </svg>
                </div>
              </div>
              <div className="space-y-3">
                <input
                  ref={fileRef}
                  type="file"
                  accept="application/pdf"
                  className="w-full text-sm text-slate-300 file:mr-4 file:rounded-full file:border-0 file:bg-slate-200 file:px-4 file:py-2 file:text-xs file:font-semibold file:text-slate-900 cursor-pointer"
                  onChange={(event) =>
                    setFileName(event.target.files?.[0]?.name ?? null)
                  }
                />
                <div className="flex items-center justify-between text-xs text-slate-400">
                  <span>{fileName ?? "No file selected"}</span>
                  <span>
                    {status === "uploading"
                      ? "Uploading"
                      : status === "processing"
                      ? "Analyzing"
                      : status === "completed"
                      ? "Ready"
                      : "Idle"}
                  </span>
                </div>
                <button
                  onClick={uploadDocument}
                  className="w-full rounded-full bg-emerald-400/90 px-4 py-2 text-sm font-semibold text-slate-900 transition hover:bg-emerald-300"
                >
                  Send for Analysis
                </button>
                {error && <p className="text-xs text-rose-300">{error}</p>}
              </div>
            </div>

            <div className="glass-card space-y-4">
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold text-white">
                  Privacy Control
                </h2>
                <button
                  onClick={purgeData}
                  className="rounded-full border border-rose-300/40 px-4 py-1 text-xs font-semibold text-rose-200 transition hover:border-rose-300 hover:text-rose-100"
                >
                  Nuke Data
                </button>
              </div>
              <p className="text-sm text-slate-300">
                Purge local cache and clear the analysis history instantly.
              </p>
              <div className="flex items-center gap-3 text-xs text-slate-400">
                <span className="h-2 w-2 rounded-full bg-emerald-400" />
                <span>On-device processing only</span>
              </div>
            </div>
          </div>

          <div className="glass-card flex h-[460px] flex-col relative">
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <div>
                <h2 className="text-lg font-semibold text-white">
                  Intelligence Feed
                </h2>
                <p className="text-xs text-slate-400">
                  Ask questions and track responses with source attribution.
                </p>
              </div>
              <div className="flex items-center gap-4">
                <div className="flex items-center gap-2 text-xs text-slate-400">
                  <span className={`brain-icon ${isChatting ? "pulse" : ""}`} />
                  <span>{isChatting ? "Thinking" : "Standby"}</span>
                </div>
                <button
                  onClick={() => setIsModalOpen(true)}
                  className="hidden rounded border border-slate-700 bg-slate-800/50 px-3 py-1 text-xs font-semibold text-slate-300 transition hover:bg-slate-700 hover:text-white md:block"
                >
                  Expand View
                </button>
              </div>
            </div>

            <div className="flex-1 overflow-y-auto py-4 pr-2">
              {renderChatMessages()}
              <div ref={chatEndRef} />
            </div>
            {renderChatInputBar()}
          </div>
        </section>

        {/* Added flex, flex-col, and justify-center to vertically center these elements */}
        <aside className="w-full flex flex-col justify-center space-y-6 lg:w-[320px]">
          <div className="glass-card space-y-4">
            <h2 className="text-lg font-semibold text-white">Hardware Specs</h2>
            <div className="space-y-3 text-xs text-slate-300">
              {infoEntries.map(([key, value]) => (
                <div key={key} className="flex items-center justify-between gap-4">
                  <span className="uppercase tracking-[0.2em] text-slate-500">
                    {key}
                  </span>
                  <span className="text-right text-slate-200">{value}</span>
                </div>
              ))}
            </div>
          </div>

          {/* GITHUB TEAM BOX */}
          <div className="glass-card space-y-4">
            <h2 className="text-lg font-semibold text-white">Project & Team</h2>
            <div className="flex flex-col gap-4 text-sm">
              <a
                href="https://github.com/adityaMachal/aura-amd"
                target="_blank"
                rel="noopener noreferrer"
                className="group flex items-center justify-between rounded-lg border border-slate-700 bg-slate-800/50 p-3 transition hover:border-emerald-500/50 hover:bg-slate-800"
              >
                <div className="flex items-center gap-3 text-slate-300 group-hover:text-emerald-400">
                  <svg viewBox="0 0 24 24" fill="currentColor" className="h-5 w-5"><path d="M12 2A10 10 0 0 0 2 12c0 4.42 2.87 8.17 6.84 9.5.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34-.45-1.15-1.11-1.46-1.11-1.46-.9-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.87 1.52 2.34 1.07 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.92 0-1.11.38-2 1.03-2.71-.1-.25-.45-1.29.1-2.64 0 0 .84-.27 2.75 1.02.79-.22 1.65-.33 2.5-.33.85 0 1.71.11 2.5.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.35.2 2.39.1 2.64.65.71 1.03 1.6 1.03 2.71 0 3.82-2.34 4.66-4.57 4.91.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0 0 12 2z"/></svg>
                  <span className="font-semibold">Repository</span>
                </div>
                <span className="text-slate-500">↗</span>
              </a>

              <div className="space-y-2">
                <p className="text-xs uppercase tracking-[0.2em] text-slate-500">Contributors</p>
                {[
                  { name: "Peeyush", url: "https://github.com/breadOnLaptop" },
                  { name: "Aditya", url: "https://github.com/adityaMachal" },
                  { name: "Karthikeya", url: "https://github.com/Bharadwaj-Karthikeya" }
                ].map((member, i) => (
                  <a
                    key={i}
                    href={member.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center justify-between rounded px-2 py-1 text-slate-400 transition hover:bg-slate-800/50 hover:text-emerald-400"
                  >
                    <span>{member.name}</span>
                    <span className="text-xs text-slate-600">↗</span>
                  </a>
                ))}
              </div>
            </div>
          </div>
        </aside>
      </div>

      {/* Focus Mode Chat Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 p-4 backdrop-blur-sm transition-opacity duration-300">
          <div className="glass-card flex h-full max-h-[85vh] w-full max-w-4xl flex-col bg-slate-900 border border-slate-700 shadow-2xl relative">
            <div className="flex items-center justify-between border-b border-slate-800 pb-4">
              <div>
                <h2 className="text-xl font-semibold text-white">Focus Mode</h2>
                <p className="text-xs text-slate-400">Full-screen document analysis</p>
              </div>
              <button
                onClick={() => setIsModalOpen(false)}
                className="rounded-full bg-slate-800 p-2 text-slate-400 transition hover:bg-slate-700 hover:text-white"
              >
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <line x1="18" y1="6" x2="6" y2="18"></line>
                  <line x1="6" y1="6" x2="18" y2="18"></line>
                </svg>
              </button>
            </div>

            <div className="flex-1 overflow-y-auto py-6 pr-4">
              {renderChatMessages()}
              <div ref={modalChatEndRef} />
            </div>

            <div className="pt-2">
              {renderChatInputBar()}
            </div>
          </div>
        </div>
      )}

      {toast && <Toast message={toast} />}
    </div>
  );
}
