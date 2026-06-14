# FastAPI Backend Setup

This backend runs a FastAPI service with PostgreSQL provided via Docker Compose.

---

## 1. Start PostgreSQL

Run the database:

```bash id="k1q9x2"
docker compose -f docker-compose.yaml up
```

Run in detached mode:

```bash id="p4m8s1"
docker compose -f docker-compose.yaml up -d
```

Stop the database:

```bash id="c7v0n3"
docker compose -f docker-compose.yaml down
```

---

## 2. Run FastAPI locally

Install dependencies:

```bash id="d2x6l8"
pip install -r requirements.txt
```

Start the server:

```bash id="r9t3w5"
uvicorn backend.app.main:app --reload
```

Server URL:

```text id="h6j1k4"
http://127.0.0.1:8000
```

---

## 3. API documentation

When the server is running:

* Swagger UI:

```text id="s8n2v5"
http://127.0.0.1:8000/docs
```

* ReDoc:

```text id="q3p7m6"
http://127.0.0.1:8000/redoc
```