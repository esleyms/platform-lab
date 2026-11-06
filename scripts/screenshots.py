"""Capturas de tela do laboratório rodando (usadas no README).

Roda depois que a plataforma está saudável e recebeu tráfego. Lê as credenciais
do cluster e do diretório de estado, como o `make urls`.

    python scripts/screenshots.py docs/img
"""

import base64
import json
import os
import ssl
import subprocess
import sys
import urllib.request
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

STATE_DIR = Path(os.environ.get("STATE_DIR", Path.home() / ".config/platform-lab"))
VIEWPORT = {"width": 1600, "height": 900}


def kubectl_secret(namespace: str, name: str, key: str) -> str:
    out = subprocess.run(  # noqa: S603
        ["kubectl", "-n", namespace, "get", "secret", name, "-o", f"jsonpath={{.data.{key}}}"],  # noqa: S607
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return base64.b64decode(out).decode()


def argocd_token(password: str) -> str:
    ctx = ssl.create_default_context(cafile=str(STATE_DIR / "ca.crt"))
    req = urllib.request.Request(
        "https://argocd.localhost/api/v1/session",
        data=json.dumps({"username": "admin", "password": password}).encode(),
        headers={"content-type": "application/json"},
    )
    with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:  # noqa: S310
        return json.load(resp)["token"]


def settle(page: Page, ms: int = 4000) -> None:
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(ms)


def main(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    argo_pw = kubectl_secret("argocd", "argocd-initial-admin-secret", "password")
    grafana_pw = (STATE_DIR / "grafana-admin-password").read_text().strip()
    basic = base64.b64encode(f"admin:{grafana_pw}".encode()).decode()

    with sync_playwright() as pw:
        browser = pw.chromium.launch()

        argo = browser.new_context(viewport=VIEWPORT, ignore_https_errors=True)
        argo.add_cookies(
            [
                {
                    "name": "argocd.token",
                    "value": argocd_token(argo_pw),
                    "domain": "argocd.localhost",
                    "path": "/",
                    "secure": True,
                }
            ]
        )
        page = argo.new_page()
        page.goto("https://argocd.localhost/applications?view=tiles")
        page.get_by_text("Healthy").first.wait_for(timeout=60_000)
        settle(page)
        page.screenshot(path=out_dir / "argocd-applications.png")

        page.goto("https://argocd.localhost/applications/argocd/api-dev?view=tree")
        settle(page, 6000)
        page.screenshot(path=out_dir / "argocd-api-dev.png")
        argo.close()

        graf = browser.new_context(
            viewport=VIEWPORT,
            ignore_https_errors=True,
            extra_http_headers={"Authorization": f"Basic {basic}"},
        )
        page = graf.new_page()
        page.goto(
            "https://grafana.localhost/d/platform-lab-api"
            "?orgId=1&from=now-15m&to=now&refresh=&kiosk"
        )
        settle(page, 8000)
        page.screenshot(path=out_dir / "grafana-slo.png")
        graf.close()

        browser.close()
    for f in sorted(out_dir.glob("*.png")):
        print(f"{f} ({f.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "screenshots"))
