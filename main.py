import os
from dotenv import load_dotenv
import ollama
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse

load_dotenv()

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "mistral")
ollama.base_url = OLLAMA_HOST

app = FastAPI(title="Email Extractor API")

PROMPT_TEMPLATE = """You are an assistant that extracts the main composed message from email replies.

Instructions:
- Extract ONLY the text that begins with a **salutation** like “Hi”, “Hello”, “Hey”, etc. It must **start exactly at that greeting**.
- Continue extracting text **until the closing line that contains a sign-off**, such as “Thanks”, “Thank you”, “Regards”, or the sender's **name** (e.g., "Meghan", "John", etc.).
- **Do NOT include any previous email replies, headers, or signatures.**
- **Do NOT extract anything before the salutation or after the closing name/sign-off.**
- The result must be natural and human-readable, maintaining all original **line breaks** and paragraph formatting.

Input:
---
{body}
---

Output:
Only the body of the message, from greeting to sign-off, nothing else."""


def extract(txt: str, model: str) -> str:
    prompt = PROMPT_TEMPLATE.format(body=txt)
    res = ollama.chat(model=model, messages=[{"role": "user", "content": prompt}])
    return res["message"]["content"].strip()


@app.post("/extract", response_class=JSONResponse)
async def api(request: Request):
    try:
        data = await request.json()
        email_text = data.get("description", "")
        if not email_text:
            raise HTTPException(400, "Missing 'description' in request body")

        cleaned = extract(email_text, OLLAMA_MODEL)
        return {"content": cleaned}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ollama error: {e}")
