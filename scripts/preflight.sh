#!/usr/bin/env bash
# Falha cedo e com mensagem clara, em vez de deixar o erro aparecer no meio do terraform.
set -euo pipefail

fail=0
need() {
  if command -v "$1" >/dev/null 2>&1; then
    printf "  %-10s ok\n" "$1"
  else
    printf "  %-10s FALTANDO\n" "$1"; fail=1
  fi
}

echo "Ferramentas:"
for t in docker kubectl helm terraform kind openssl; do need "$t"; done

echo "Docker:"
if ! docker info >/dev/null 2>&1; then
  echo "  daemon inacessível (Docker parado ou usuário sem permissão)"; exit 1
fi
mem_gb=$(( $(docker info --format '{{.MemTotal}}') / 1024 / 1024 / 1024 ))
echo "  memória disponível para containers: ${mem_gb} GiB"
if (( mem_gb < 10 )); then
  echo "  AVISO: menos de 10 GiB. Aumente o limite do Docker Desktop/WSL ou espere pods em OOMKilled."
fi

if [[ -r /proc/sys/fs/inotify/max_user_watches ]]; then
  watches=$(cat /proc/sys/fs/inotify/max_user_watches)
  instances=$(cat /proc/sys/fs/inotify/max_user_instances)
  echo "inotify: watches=${watches} instances=${instances}"
  if (( watches < 524288 || instances < 512 )); then
    echo "  AVISO: limites baixos causam 'too many open files' em clusters kind com vários nós."
    echo "  sudo sysctl fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=512"
  fi
fi

for port in 80 443; do
  if (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null) | grep -qE "[:.]${port}\s"; then
    echo "AVISO: porta ${port} já está em uso no host; ajuste http_host_port/https_host_port no Terraform."
  fi
done

exit $fail
