FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# Shell form so Railway's $PORT variable is expanded correctly
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}
