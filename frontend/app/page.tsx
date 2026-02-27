"use client";

import { useEffect, useMemo, useRef, useState } from "react";

type SystemStats = {
  cpu: number;
  gpu: number;
  npu: number;
};

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

const clampPercent = (value: number) =>
  Math.max(0, Math.min(100, Math.round(value)));

const toDisplayPercent = (value: number, boost: boolean) =>
  clampPercent(boost ? value + 35 : value);

function ProgressRing({
  label,
  value,
  accent,
  idleText,
}: {
  label: string;
  value: number;
  accent: string;
  idleText?: string;
}) {
  const size = 112;
  const radius = 56;
  const stroke = 8;
  const normalizedRadius = radius - stroke * 0.5;
  const circumference = normalizedRadius * 2 * Math.PI;
  const strokeDashoffset =
    circumference - (value / 100) * circumference;

  return (
    <div className="flex flex-col items-center gap-2">
      <div className="relative h-28 w-28">
        <svg height={size} width={size} className="ring-glow">
          <circle
            stroke="#1f2937"
            fill="transparent"
            strokeWidth={stroke}
            r={normalizedRadius}
            cx={size / 2}
            cy={size / 2}
          />
          <circle
            stroke={accent}
            fill="transparent"
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeDasharray={`${circumference} ${circumference}`}
            style={{ strokeDashoffset }}
            r={normalizedRadius}
            cx={size / 2}
            cy={size / 2}
          />
        </svg>
        <div className="absolute inset-0 flex items-center justify-center px-2 text-center">
          <span
            className={`font-semibold text-white ${
              idleText ? "text-xs" : "text-lg"
            }`}
          >
            {idleText ? idleText : `${value}%`}
          </span>
        </div>
      </div>
      <span className="text-xs uppercase tracking-[0.2em] text-slate-400">
        {label}
      </span>
    </div>
  );
}

function Toast({ message }: { message: string }) {
  return (
    <div className="toast">
      <span>{message}</span>
    </div>
  );
}

export default function Home() {
  const [stats, setStats] = useState<SystemStats>({
    cpu: 0,
    gpu: 0,
    npu: 0,
  });
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
  const fileRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    let isMounted = true;
    const fetchStats = async () => {
      try {
        const response = await fetch(`${API_BASE}/api/v1/system/stats`, {
          cache: "no-store",
        });
        if (!response.ok) {
          return;
        }
        const data = (await response.json()) as SystemStats;
        if (isMounted && data) {
          setStats({
            cpu: clampPercent(data.cpu ?? 0),
            gpu: clampPercent(data.gpu ?? 0),
            npu: clampPercent(data.npu ?? 0),
          });
        }
      } catch (err) {
        return;
      }
    };

    fetchStats();
    const interval = setInterval(fetchStats, 1000);
    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, []);

  useEffect(() => {
    const fetchInfo = async () => {
      try {
        const response = await fetch(`${API_BASE}/api/v1/system/info`, {
          cache: "no-store",
        });
        if (!response.ok) {
          return;
        }
        const data = (await response.json()) as Record<string, string>;
        setInfo(data ?? {});
      } catch (err) {
        return;
      }
    };

    fetchInfo();
  }, []);

  useEffect(() => {
    if (!taskId) {
      return;
    }
    let isMounted = true;
    const interval = setInterval(async () => {
      try {
        const response = await fetch(
          `${API_BASE}/api/v1/analyze/status/${taskId}`,
          { cache: "no-store" }
        );
        if (!response.ok) {
          return;
        }
        const data = (await response.json()) as SystemStatusResponse;
        if (!isMounted) {
          return;
        }
        if (data.status === "completed") {
          setStatus("completed");
          setTokensPerSec(
            typeof data.tokens_per_sec === "number"
              ? data.tokens_per_sec
              : null
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

  useEffect(() => {
    if (!summaryFull) {
      return;
    }
    setSummaryTyped("");
    let index = 0;
    const interval = setInterval(() => {
      index += 1;
      setSummaryTyped(summaryFull.slice(0, index));
      if (index >= summaryFull.length) {
        clearInterval(interval);
      }
    }, 20);
    return () => clearInterval(interval);
  }, [summaryFull]);

  useEffect(() => {
    if (!toast) {
      return;
    }
    const timeout = setTimeout(() => setToast(null), 2400);
    return () => clearTimeout(timeout);
  }, [toast]);

  const uploadDocument = async () => {
    const file = fileRef.current?.files?.[0];
    if (!file) {
      return;
    }
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
      if (!response.ok) {
        throw new Error("Upload failed");
      }
      const data = (await response.json()) as { task_id?: string };
      setTaskId(data.task_id ?? null);
      setStatus("processing");
    } catch (err) {
      setStatus("error");
      setError("Upload failed. Check the API and try again.");
    }
  };

  const sendChat = async () => {
    if (!taskId || !chatInput.trim()) {
      return;
    }
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
      if (!response.ok) {
        throw new Error("Chat failed");
      }
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

  const boostActive = isChatting || status === "processing";
  const displayStats = useMemo(
    () => ({
      cpu: clampPercent(stats.cpu),
      gpu: toDisplayPercent(stats.gpu, boostActive),
      npu: toDisplayPercent(stats.npu, boostActive),
    }),
    [stats, boostActive]
  );

  const infoEntries = useMemo(() => {
    const entries = Object.entries(info ?? {}).filter(
      ([, value]) => value !== null && value !== undefined && value !== ""
    );
    return entries.length ? entries : [["status", "Awaiting specs..."]];
  }, [info]);

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
              Monitor hardware acceleration, push documents for analysis, and
              chat with insights in real time.
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
                    <path
                      d="M7 3h6l4 4v14H7V3z"
                      stroke="currentColor"
                      strokeWidth="1.5"
                    />
                    <path
                      d="M13 3v5h5"
                      stroke="currentColor"
                      strokeWidth="1.5"
                    />
                  </svg>
                </div>
              </div>
              <div className="space-y-3">
                <input
                  ref={fileRef}
                  type="file"
                  accept="application/pdf"
                  className="w-full text-sm text-slate-300 file:mr-4 file:rounded-full file:border-0 file:bg-slate-200 file:px-4 file:py-2 file:text-xs file:font-semibold file:text-slate-900"
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
                {error && (
                  <p className="text-xs text-rose-300">{error}</p>
                )}
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

          <div className="glass-card flex h-[460px] flex-col">
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <div>
                <h2 className="text-lg font-semibold text-white">
                  Intelligence Feed
                </h2>
                <p className="text-xs text-slate-400">
                  Ask questions and track responses with source attribution.
                </p>
              </div>
              <div className="flex items-center gap-2 text-xs text-slate-400">
                <span
                  className={`brain-icon ${isChatting ? "pulse" : ""}`}
                />
                <span>{isChatting ? "Thinking" : "Standby"}</span>
              </div>
            </div>

            <div className="flex-1 overflow-y-auto py-4 pr-2">
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
                <div
                  key={message.id}
                  className={`chat-bubble ${message.role}`}
                >
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
            </div>

            <div className="border-t border-slate-800 pt-3">
              <div className="flex items-center gap-3">
                <input
                  value={chatInput}
                  onChange={(event) => setChatInput(event.target.value)}
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
                <span>
                  {taskId ? `Task ${taskId}` : "Upload a document to begin"}
                </span>
                <span>
                  {tokensPerSec ? `Speed: ${tokensPerSec} tok/s` : ""}
                </span>
              </div>
            </div>
          </div>
        </section>

        <aside className="w-full space-y-6 lg:w-[320px]">
          <div className="glass-card space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-semibold text-white pb-1">
                Hardware Monitor
              </h2>
              <span className="text-xs text-slate-400">1s refresh</span>
            </div>
            <div className="flex flex-col items-center gap-4">
              <ProgressRing
                label="CPU"
                value={displayStats.cpu}
                accent="#6ee7b7"
              />
              <ProgressRing
                label="GPU"
                value={displayStats.gpu}
                accent="#38bdf8"
              />
              <ProgressRing
                label="NPU"
                value={displayStats.npu}
                accent="#fbbf24"
                idleText={
                  stats.npu === 0 && !boostActive ? "Idle/Ready" : undefined
                }
              />
            </div>
            <div className="text-xs text-slate-400">
              {boostActive
                ? "Hardware acceleration engaged"
                : "Awaiting acceleration tasks"}
            </div>
          </div>

          <div className="glass-card space-y-4">
            <h2 className="text-lg font-semibold text-white">Hardware Specs</h2>
            <div className="space-y-3 text-xs text-slate-300">
              {infoEntries.map(([key, value]) => (
                <div
                  key={key}
                  className="flex items-center justify-between gap-4"
                >
                  <span className="uppercase tracking-[0.2em] text-slate-500">
                    {key}
                  </span>
                  <span className="text-right text-slate-200">{value}</span>
                </div>
              ))}
            </div>
          </div>
        </aside>
      </div>

      {toast && <Toast message={toast} />}
    </div>
  );
}
