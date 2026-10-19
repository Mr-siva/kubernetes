from fastapi import FastAPI
import socket

app = FastAPI()

@app.get("/")
def root():
    return {"message": "Hello from ArgoCD GitOps!", "pod": socket.gethostname()}

@app.get("/health")
def health():
    return {"status": "ok"}
