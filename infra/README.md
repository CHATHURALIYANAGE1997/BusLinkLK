# infra

Everything needed to run BusLink outside the IDE lives here.

| Path | What it will hold | Arrives in |
|---|---|---|
| `docker-compose.yml` | Local infrastructure: Kafka (KRaft), Schema Registry, Kafka UI, PostgreSQL + PostGIS, Redis | SCRUM-19 |
| `kafka/` | Topic provisioning (partitions, cleanup policy, retention) | SCRUM-20 |
| `observability/` | Prometheus, Grafana and Jaeger configuration | Sprint 6 |
| `helm/` | Helm charts for Kubernetes | Sprint 7 |
