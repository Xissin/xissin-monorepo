import os
import logging
import uvicorn

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    logging.info(f"▶️   start.py → launching main_backend:app on port {port}")
    uvicorn.run("main_backend:app", host="0.0.0.0", port=port)