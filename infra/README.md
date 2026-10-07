# infra

Everything needed to run BusLink outside the IDE lives here.

| Path | What it holds | Status |
|---|---|---|
| `docker-compose.yml` | Local infrastructure: Kafka (KRaft), Schema Registry, Kafka UI, PostgreSQL + PostGIS, Redis | Done (SCRUM-19) |
| `postgres/` | Init script: one database and owner role per service, PostGIS for `route` | Done (SCRUM-19) |
| `.env.example` | Optional overrides: image versions, host ports, local passwords | Done (SCRUM-19) |
| `kafka/` | Topic provisioning (partitions, cleanup policy, retention) | SCRUM-20 |
| `observability/` | Prometheus, Grafana and Jaeger configuration | Sprint 6 |
| `helm/` | Helm charts for Kubernetes | Sprint 7 |

## Local infrastructure

> Local development only: one Kafka broker, no TLS, throwaway passwords.
> Cloud environments run the same application images with different configuration.

Run from the repository root:

```sh
docker compose -f infra/docker-compose.yml up -d --wait   # start, wait until healthy
docker compose -f infra/docker-compose.yml ps             # status
docker compose -f infra/docker-compose.yml logs -f kafka  # follow one service's logs
docker compose -f infra/docker-compose.yml down           # stop, keep data
docker compose -f infra/docker-compose.yml down -v        # stop and delete all data
```

| Service | From your laptop / IDE | From another container | Notes |
|---|---|---|---|
| Kafka | `localhost:9092` | `kafka:29092` | KRaft, single broker + controller |
| Schema Registry | http://localhost:8091 | http://schema-registry:8081 | Compatibility: `BACKWARD` |
| Kafka UI | http://localhost:8089 | | Topics, messages, consumer groups, schemas |
| PostgreSQL + PostGIS | `localhost:5432` | `postgres:5432` | Admin `buslink` / `buslink` |
| Redis | `localhost:6379` | `redis:6379` | Append-only file enabled |

Host ports stay out of 8080–8090 on purpose, which is reserved for the BusLink services.

### Databases

Each service owns its own database and never reads another service's tables.

| Database | Owner / password | Extensions |
|---|---|---|
| `route` | `route` / `route` | PostGIS |
| `fare` | `fare` / `fare` | |
| `wallet` | `wallet` / `wallet` | |
| `analytics` | `analytics` / `analytics` | |

The init script runs only on the first start with an empty volume. If you change it, run `down -v` and start again.

### Overrides

Port already taken, or want to try another image version? Copy the example file and edit it. `infra/.env` is git-ignored.

```sh
cp infra/.env.example infra/.env          # Windows: copy infra\.env.example infra\.env
```

### Verified in CI

`.github/workflows/infra-smoke.yml` runs on every change under `infra/`. It starts the stack on a GitHub runner, then produces and consumes a Kafka message, checks Schema Registry, Kafka UI, the four databases with PostGIS, and Redis.
