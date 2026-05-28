# AntGain

AntGain lets you share unused network bandwidth from your computer or server and earn rewards. Install the node, sign in with your API key, and run it in the background.

**Get your API key:** [antgain.app → Settings](https://antgain.app/dashboard/settings)

---

## Guides

| Topic | Document |
|-------|----------|
| Install on **Linux** (PC, VPS, server) | [docs/linux.md](docs/linux.md) |
| Install on **Linux ARM** (RK3528, armhf, etc.) | [docs/linux-arm.md](docs/linux-arm.md) |
| Install on **macOS** | [docs/macos.md](docs/macos.md) |
| Run in **Docker** | [docs/docker.md](docs/docker.md) |
| **CLI commands** (all platforms) | [docs/commands.md](docs/commands.md) |

**Docker image:** [Docker Hub — pinors/antgain-cli](https://hub.docker.com/r/pinors/antgain-cli)

---

## What you need

- An AntGain account and API key  
- A supported system (see the platform guides above)  
- For Docker: a **fixed** device UUID per container (explained in [docs/docker.md](docs/docker.md))

---

## Publishing docs on antgain.app

User-facing docs are rendered at [docs.antgain.app](https://docs.antgain.app) from the `antgain-web` repo. After editing files under `docs/`, run in `antgain-web`:

```bash
pnpm run sync:installer-docs
```

---

## License

MIT
