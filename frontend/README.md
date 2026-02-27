# Aura-AMD Dashboard (Frontend)

A Next.js App Router frontend for the Aura-AMD local AI acceleration dashboard. It integrates with the Go backend to monitor hardware usage, upload documents, and chat with RAG responses.

## Setup

```bash
npm install
```

## Environment

Optional API base override:

```bash
NEXT_PUBLIC_API_BASE=http://localhost:8080
```

## Run

```bash
npm run dev
```

## Build

```bash
npm run build
npm run start
```

## Lint

```bash
npm run lint
```

## API Expectations

- `GET /api/v1/system/stats` (polled every 1000ms)
- `GET /api/v1/system/info`
- `POST /api/v1/analyze/upload` (FormData PDF upload)
- `GET /api/v1/analyze/status/{task_id}` (polled every 2 seconds)
- `POST /api/v1/analyze/chat`
- `DELETE /api/v1/analyze/purge/{task_id}`
