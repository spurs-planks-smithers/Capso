FROM python:3.12.12-slim-bookworm@sha256:2986c55feb36e6cae00fa1fefb454283e4b33f35e75ff8bdd123b134130be301

# Debian snapshot pins antivirus and OCR dependencies for repeatable builds.
RUN printf 'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20261025T000000Z bookworm main\ndeb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/20261025T000000Z bookworm-security main\n' > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends clamav clamav-freshclam tesseract-ocr tesseract-ocr-eng \
    && rm -rf /var/lib/apt/lists/* /var/lib/clamav/* \
    && useradd --system --uid 10001 --no-create-home scanner

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir torch==2.9.0 --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir -r /app/requirements.txt
COPY app /app
COPY model /opt/prompt-guard
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 OMP_NUM_THREADS=1 TOKENIZERS_PARALLELISM=false
WORKDIR /app
USER 10001:10001
EXPOSE 8080
CMD ["python", "server.py"]
