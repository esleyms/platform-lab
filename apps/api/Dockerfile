# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.13

# ---- build: resolve e compila dependências num venv isolado ----
FROM python:${PYTHON_VERSION}-slim AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
COPY requirements.txt .
RUN pip install --require-virtualenv -r requirements.txt \
 && python -m pip uninstall -y pip
COPY src/ ./src/

# ---- runtime: só o venv e o código, usuário sem privilégios ----
FROM python:${PYTHON_VERSION}-slim AS runtime
ARG VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/esleyms/platform-lab" \
      org.opencontainers.image.description="platform-lab api" \
      org.opencontainers.image.licenses="MIT"

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src \
    APP_VERSION=${VERSION}

# pip, setuptools e ensurepip não são usados em runtime. Removê-los tira do scan as
# dependências que eles embutem (urllib3, msgpack...) e um instalador de pacotes da imagem.
RUN python -m pip uninstall -y pip setuptools wheel 2>/dev/null; \
    rm -rf /usr/local/lib/python*/ensurepip /usr/local/bin/pip* \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=build /opt/venv /opt/venv
COPY --from=build --chown=root:root /build/src /app/src

USER 10001:10001
WORKDIR /app
EXPOSE 8080

# exec form: uvicorn vira PID 1 e recebe o SIGTERM do kubelet
ENTRYPOINT ["uvicorn", "platform_api.main:app", "--factory", "--host", "0.0.0.0", "--port", "8080", "--no-access-log", "--timeout-graceful-shutdown", "20"]
