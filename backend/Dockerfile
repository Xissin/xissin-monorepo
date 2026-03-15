FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# SERVICE=web  → runs the FastAPI backend (default)
# SERVICE=worker → runs the auto_edit_bot
CMD ["sh", "-c", "if [ \"$SERVICE\" = 'worker' ]; then python auto_edit_bot.py; else python start.py; fi"]
