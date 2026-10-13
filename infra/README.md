# infra

Everything needed to run BusLink outside the IDE lives here.

| Path | What it holds | Status |
|---|---|---|
| `docker-compose.yml` | Local infrastructure: Kafka (KRaft), Schema Registry, Kafka UI, PostgreSQL + PostGIS, Redis | Done (SCRUM-19) |
| `postgres/` | Init script: one database and owner role per service, PostGIS for `route` | Done (SCRUM-19) |
| `.env.example` | Optional overrides: image versions, host ports, local passwords | Done (SCRUM-19) |
| `kafka/` | Topic provisioning: `topics.conf` (partitions, cleanup policy, retention) applied by `create-topics.sh` | Done (SCRUM-20) |
| `observability/` | Prometheus, Grafana and Jaeger configuration | Sprint 6 |
| `helm/` | Helm charts for Kubernetes | Sprint 7 |

## Local infrastructure

> Local development only: one Kafka broker, no TLS, throwaway passwords.
> Cloud environments run the same application images with different configuration.

Run from the repository root:

```sh
docker compose -f infra/docker-compose.yml up -d --wait                # core only, wait until healthy
docker compose -f infra/docker-compose.yml --profile ui up -d --wait   # core + Kafka UI
docker compose -f infra/docker-compose.yml ps             # status
docker compose -f infra/docker-compose.yml logs -f kafka  # follow one service's logs
docker compose -f infra/docker-compose.yml down           # stop, keep data
docker compose -f infra/docker-compose.yml down -v        # stop and delete all data
```

| Service | From your laptop / IDE | From another container | Notes |
|---|---|---|---|
| Kafka | `localhost:9092` | `kafka:29092` | KRaft, single broker + controller |
| Schema Registry | http://localhost:8091 | http://schema-registry:8081 | Compatibility: `BACKWARD` |
| Kafka UI | http://localhost:8089 | | Profile `ui`. Topics, messages, consumer groups, schemas |
| PostgreSQL + PostGIS | `localhost:5432` | `postgres:5432` | Admin `buslink` / `buslink` |
| Redis | `localhost:6379` | `redis:6379` | Append-only file enabled |

### Profiles

The default start is a lean core so it fits on a laptop with limited memory. Extras are opt-in.

| Profile | Adds | Approx. memory |
|---|---|---|
| *(none)* | kafka, schema-registry, postgres, redis | ~1.5 GB |
| `ui` | kafka-ui | +0.3 GB |
| `observability` | Prometheus, Grafana, Jaeger (Sprint 6) | later |

Set `COMPOSE_PROFILES=ui` in `infra/.env` to include Kafka UI every time (`.env.example` already does).

Host ports stay out of 8080–8090 on purpose, which is reserved for the BusLink services.

### Kafka topics

Topics are never auto-created (`auto.create.topics.enable=false`). They are declared in
[`kafka/topics.conf`](kafka/topics.conf), and the one-shot `kafka-init` container applies that file
every time the stack starts, then exits.

| Topic | Key | Partitions | Cleanup / retention | Producer |
|---|---|---|---|---|
| `telemetry.gps.raw` | busId | 12 | delete, 3 days | ingestion-gateway |
| `fare.taps` | cardId | 6 | delete, 30 days | ingestion-gateway |
| `route.updated` | routeId | 1 | compact | route-service |
| `bus.position` | busId | 12 | compact | tracking-service |
| `bus.eta` | stopId | 6 | delete, 1 day | tracking-service |
| `bus.occupancy` | busId | 6 | compact | tracking-service |
| `fare.trip-completed` | cardId | 6 | delete, 30 days | fare-service |
| `wallet.debit-requested` | cardId | 6 | delete, 30 days | fare-service (outbox) |
| `wallet.debited` | cardId | 6 | delete, 30 days | wallet-service (outbox) |
| `wallet.debit-failed` | cardId | 6 | delete, 30 days | wallet-service (outbox) |
| `wallet.denylist` | cardId | 1 | compact | wallet-service |

Retry and dead-letter topics (`<topic>.retry-*`, `<topic>.dlt`) are created by Spring Kafka itself.

To add or change a topic, edit `topics.conf` and re-run the init step. It is idempotent:
missing topics are created, partitions are raised, changed configs are applied, and everything
else is left alone. Partitions can never be reduced; the script warns instead.

```sh
docker compose -f infra/docker-compose.yml run --rm kafka-init
# kafka-init: done: 0 created, 1 updated, 10 unchanged, 0 warnings
```

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

`.github/workflows/infra-smoke.yml` runs on every change under `infra/`. It starts the stack on a GitHub runner, then checks that every topic in `topics.conf` exists with the right partitions and configs, that a second `kafka-init` run changes nothing, and that auto-creation is off. It also produces and consumes a Kafka message, and checks Schema Registry, Kafka UI, the four databases with PostGIS, and Redis.
