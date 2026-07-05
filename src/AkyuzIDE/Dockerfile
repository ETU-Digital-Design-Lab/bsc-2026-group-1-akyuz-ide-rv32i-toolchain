# --- Stage 1: Build Frontend ---
FROM node:20-slim AS frontend-builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npx vite build

# --- Stage 2: Final Image ---
FROM python:3.11-slim
WORKDIR /app

# Install system dependencies & Hardware tools (iverilog)
RUN apt-get update && apt-get install -y \
    iverilog \
    gcc-riscv64-unknown-elf \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend code
COPY server/ ./server/

# Copy built frontend to be served by FastAPI
COPY --from=frontend-builder /app/dist ./server/static

# Environment Variables
ENV WORKSPACE_DIR=/app/workspace
ENV IVERILOG_PATH=/usr/bin/iverilog
ENV VVP_PATH=/usr/bin/vvp
ENV PORT=8000

EXPOSE 8000

# Start Backend (which also serves the static frontend)
CMD ["python", "server/main.py"]
