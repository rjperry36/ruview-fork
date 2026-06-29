# RuView on QNAP (Container Station)

Two ways to deploy. Both run the same pinned image (`v0.8.3-esp32`).

## Option 1 — script (auto token + auto allowlist) — recommended

`../../scripts/deploy-qnap.sh` generates & persists an API token and auto-derives
`SENSING_ALLOWED_HOSTS` from the NAS LAN IP. Run it **on the NAS**:

```bash
scp -P 2222 ../../scripts/deploy-qnap.sh admin@<nas-ip>:
ssh -p 2222 admin@<nas-ip>
PORT=3010 CSI_SOURCE=simulated ./deploy-qnap.sh
```

## Option 2 — docker compose (declarative)

```bash
cp .env.example .env
#  - set RUVIEW_API_TOKEN   (openssl rand -hex 32)
#  - set SENSING_ALLOWED_HOSTS to <nas-ip>:<port>,<nas-ip>,...
docker compose up -d        # older Container Station: docker-compose up -d
```

Then open `http://<nas-ip>:3010`. Health check: `curl http://<nas-ip>:3010/health`.

## Notes

- **Secrets stay out of git** — only `.env.example` is committed; your real `.env`
  (and the token) are not.
- **Going live with an ESP32:** provision it with `--target-ip <nas-ip>`, then set
  `CSI_SOURCE=esp32` and redeploy.
- **Prereqs on the NAS:** Container Station installed, and a working default
  gateway/DNS (so Docker can pull). See `../../SETUP-COWORK.md` "Path D".
