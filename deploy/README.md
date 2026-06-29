# deploy/ — RuView deployment templates

This folder holds **reusable deployment templates**, one subfolder per target
(`qnap/`, …). They are *templates*, not live instances.

## The model

```
this fork (ruview-fork)            ← the software. Tracks upstream ruvnet/RuView.
        │  builds & publishes →  ruvnet/wifi-densepose:<tag>   (Docker image)
        ▼
deploy/<target>/                   ← reusable template (compose + .env.example, committed)
        │  copy out + fill .env →
        ▼
your real deployment               ← a project instance with real tokens/hosts (NOT in git)
```

## Rules that keep it clean

- **Templates live here; real instances live outside.** A `.env` with real
  tokens/hosts is per-project and must never be committed — only `.env.example` is.
- **Pin the image tag** in each template for reproducibility (avoid `:latest`,
  which mutates under you). Bump the tag deliberately when you adopt a release.
- **Fork the code only when you must change RuView's source.** Different
  container, ports, data source, or host = a deployment difference → new
  `deploy/<target>/` template or a separate deploy repo, *not* a source fork.

## When to graduate to a separate repo

Start with templates here. Extract a target into its own deployment repo once a
second project exists, or when an instance needs secrets/infra that shouldn't sit
beside the core. The folder copies out cleanly as that repo's seed.

## Pull upstream updates

```bash
git fetch upstream
git merge upstream/main      # or: git rebase upstream/main
```
(`upstream` = https://github.com/ruvnet/RuView.git; pushing to it is disabled.)
