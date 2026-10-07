<a id="readme-top"></a>

<div align="center">

<h1>🚌 BusLink LK</h1>

<p>
  <strong>Live bus tracking and digital fares for Sri Lanka, built as event-driven microservices on Java, Spring Boot and Apache Kafka.</strong>
  <br />
  <br />
  <a href="#architecture"><strong>Explore the docs »</strong></a>
  <br />
  <br />
  <a href="#roadmap">View Roadmap</a>
  &middot;
  <a href="https://github.com/CHATHURALIYANAGE1997/BusLinkLK/issues/new?labels=bug">Report Bug</a>
  &middot;
  <a href="https://github.com/CHATHURALIYANAGE1997/BusLinkLK/issues/new?labels=enhancement">Request Feature</a>
</p>

[![CI][ci-shield]][ci-url]
[![Status][status-shield]][jira-url]
[![Sprint][sprint-shield]][jira-url]
[![Java][java-shield]][java-url]
[![Kafka][kafka-shield]][kafka-url]

</div>

---

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#why-im-building-this">Why I'm building this</a></li>
        <li><a href="#the-hard-parts">The hard parts</a></li>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li><a href="#architecture">Architecture</a></li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>

---

## About The Project

If you've ever waited at a bus halt on Galle Road, you know the routine. You don't know when the next bus is coming, you don't know if it'll be packed, and you'd better have exact change ready for the conductor.

BusLink is my attempt at fixing that with software. Every bus gets a GPS unit and a card reader. Passengers tap a card when they get on and again when they get off, and the fare is worked out by distance, the same way stage fares work today. On top of that, the system:

* shows every bus moving live on a map, with arrival times for each stop
* tells you how full a bus is before it gets to you
* charges your digital wallet **exactly once** per trip, even if the bus was out of signal when you tapped
* gives the transport authority real numbers on which routes are overloaded, and when

I don't have real buses, of course. A **vehicle simulator** plays the part of a few hundred of them driving real routes between Galle and Colombo, complete with the annoying stuff real devices do: dropping signal, sending the same message twice, and passengers who never tap off.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Why I'm building this

I've spent the last few years building enterprise Java applications, mostly as large monoliths. I wanted a project that forced me to deal with the problems you only meet in distributed systems: keeping data consistent across services, handling messages that arrive late or twice, and proving the whole thing holds up under load. I also wanted it to be about a problem I actually see every day rather than another to-do app.

### The hard parts

These are the problems I find most interesting, and most of the design exists because of them:

* **Buses lose signal.** On rural stretches, GPS pings arrive minutes late, out of order, or twice. The tracking pipeline processes them by the time they *happened*, not when they arrived, and holds a short grace window so late pings slot back into place.
* **GPS is noisy.** A raw point can put a bus in the middle of a paddy field. Each point gets snapped onto the actual route line before it's used.
* **Card readers have to work offline.** Taps are buffered on the bus and synced later, and every reader keeps a copy of the card deny list so blocked cards are refused even with no connection.
* **People forget to tap off.** After a timeout the trip closes at the maximum fare, and if the tap-off turns up later (from an offline reader), the difference is refunded.
* **Nobody gets charged twice.** Payments go through a transactional outbox, idempotent consumers and a choreographed saga, with a double-entry ledger underneath so the books always balance.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

[![Java][java-shield]][java-url]
[![Spring Boot][spring-shield]][spring-url]
[![Apache Kafka][kafka-shield]][kafka-url]
[![PostgreSQL][postgres-shield]][postgres-url]
[![Redis][redis-shield]][redis-url]
[![Keycloak][keycloak-shield]][keycloak-url]
[![Docker][docker-shield]][docker-url]
[![Kubernetes][k8s-shield]][k8s-url]
[![Grafana][grafana-shield]][grafana-url]
[![Leaflet][leaflet-shield]][leaflet-url]

Plus Kafka Streams, Confluent Schema Registry with Avro, PostGIS, Flyway, Spring Cloud Gateway, Resilience4j, OpenTelemetry with Jaeger, Prometheus, Testcontainers, k6, Helm, Strimzi and GitHub Actions.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Architecture

The short version: buses talk to Kafka through an ingestion gateway, people talk to the services through an API gateway, and the services only ever talk to each other through Kafka events. Each service owns its own database.

```
  Bus devices (simulated)        Passenger web app            Transport authority
  GPS units + card readers       live map, arrivals, wallet   dashboards, reports
           |                              |                            |
           v                              v                            v
  +-------------------+        +-----------------------------------------------+
  | ingestion-gateway |        |  api-gateway  (Keycloak JWT, rate limiting,   |
  | device auth,      |        |               REST + WebSocket)               |
  | validation        |        +-----------------------------------------------+
  +-------------------+                               |
           |                                          v
           |              +------------------------------------------------------+
           |              |  Microservices  (Spring Boot 4, one database each)   |
           |              |                                                      |
           |              |  tracking        journey-query      route            |
           |              |  fare            wallet             notification     |
           |              |  analytics                                           |
           |              +------------------------------------------------------+
           |                                       ^   |
           |                     consume events    |   |   publish events
           v                                       |   v
  +------------------------------------------------------------------------------+
  |                Apache Kafka (KRaft)  +  Schema Registry (Avro)               |
  |   telemetry.gps.raw · fare.taps · bus.position · bus.eta · bus.occupancy     |
  |   fare.trip-completed · wallet.* · route.updated · retry + dead-letter       |
  +------------------------------------------------------------------------------+
```

Here's what each piece does:

* **ingestion-gateway** checks that a request really comes from a registered bus, validates it, and drops it onto Kafka.
* **route-service** owns the network: routes, stops, the road geometry (imported from OpenStreetMap into PostGIS) and fare stages.
* **tracking-service** is a Kafka Streams app and the heart of the project. It de-duplicates pings, puts them back in order, snaps them to the road, and works out delays, arrival times and how full each bus is.
* **journey-query-service** keeps a fast read model in Redis and pushes live updates to the map over WebSocket.
* **fare-service** pairs up tap-ons with tap-offs, works out the fare and kicks off payment.
* **wallet-service** handles top-ups, balances and the ledger, and blocks cards that can't pay.
* **notification-service** sends "your bus is 5 minutes away" alerts, receipts and low-balance warnings.
* **analytics-service** rolls everything up into ridership and crowding reports for the authority.
* **vehicle-simulator** pretends to be the buses and the passengers.

A fare, end to end, looks like this:

```
Tap on -> Tap off (or timeout: max fare) -> fare-service builds trip + fare
      -> outbox -> wallet.debit-requested -> wallet-service (skip if already seen)
            |-- balance OK  -> ledger debit -> wallet.debited -> trip PAID -> receipt
            '-- not enough  -> wallet.debit-failed -> card added to deny list
```

Bigger decisions (why Kafka, why a saga instead of distributed transactions, why a ledger instead of a balance column, and so on) are written up as short ADRs in `docs/adr/`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Getting Started

Fair warning: this is early days. Sprint 0 is about getting the foundation in place: the build and the local infrastructure work today, the services arrive over the next sprints. I'll keep this section honest as things change.

### Prerequisites

* Java 21 (Temurin or any OpenJDK build)
* Maven is optional: the repo ships with the Maven Wrapper (`mvnw`), which downloads the right Maven version on first use
* Docker Desktop (or Docker Engine with Compose v2.20+), with 6–8 GB of memory given to it
* Git

### Installation

1. Clone the repo
   ```sh
   git clone https://github.com/CHATHURALIYANAGE1997/BusLinkLK.git
   cd BusLinkLK
   ```
2. Start the local infrastructure and wait until every container is healthy
   ```sh
   docker compose -f infra/docker-compose.yml --profile ui up -d --wait
   ```
   Drop `--profile ui` to skip Kafka UI and save memory.
   | Service | Address |
   |---|---|
   | Kafka (from your IDE) | `localhost:9092` |
   | Schema Registry | http://localhost:8091 |
   | Kafka UI | http://localhost:8089 |
   | PostgreSQL + PostGIS | `localhost:5432` (databases `route`, `fare`, `wallet`, `analytics`) |
   | Redis | `localhost:6379` |

   Stop it with `docker compose -f infra/docker-compose.yml down` (add `-v` to wipe the data). More detail in [infra/README.md](infra/README.md).
3. Build and run the tests
   ```sh
   ./mvnw verify        # macOS / Linux / Git Bash
   mvnw.cmd verify      # Windows Command Prompt
   ```
4. Start the services and the simulator (coming in later sprints)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Usage

Once it's running, the plan is that you'll be able to:

* open the live map at `http://localhost:8080` and watch buses move along the Galle–Colombo road
* click a stop to see which buses are coming and how long they'll take
* top up a card, ride a simulated trip, and see the fare come out of the wallet
* turn on the simulator's chaos mode and watch the system cope with dropped signal and duplicate messages
* follow a single trip across every service in Jaeger, and watch lag and latency in Grafana

Screenshots and a short demo video will go here as the pieces come together.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Roadmap

I'm working in two-week sprints and tracking everything in Jira.

- [ ] **Sprint 0 (6–20 Oct 2026):** repo, CI, local infrastructure, real Galle routes in PostGIS
- [ ] **Sprint 1 (20 Oct–3 Nov):** simulated buses streaming GPS and taps into Kafka
- [ ] **Sprint 2 (3–17 Nov):** turning messy GPS into clean, ordered bus positions
- [ ] **Sprint 3 (17 Nov–1 Dec):** live map with arrival times
- [ ] **Sprint 4 (1–15 Dec):** wallet, ledger and the payment saga
- [ ] **Sprint 5 (15–29 Dec):** fare edge cases (offline readers, missing tap-offs, outages) and crowding
- [ ] **Sprint 6 (29 Dec–12 Jan):** security, tracing, dashboards and notifications
- [ ] **Sprint 7 (12–26 Jan 2027):** Kubernetes, a 5,000-bus load test and chaos testing
    - [ ] write up the results with real numbers

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Contributing

This is a personal learning project, but if you spot something wrong or have an idea, I'd genuinely like to hear it. Open an issue, or:

1. Branch off `main` (`git checkout -b feature/SCRUM-<n>-short-name`)
2. Commit your changes, with the Jira key in the message (`git commit -m "SCRUM-<n> Add something useful"`)
3. Push the branch (`git push origin feature/SCRUM-<n>-short-name`)
4. Open a pull request into `main`
5. GitHub Actions builds and tests the branch (`./mvnw verify` on JDK 21); the pull request can be merged once the **build** check is green

I use trunk-based development: feature branches are short-lived, every change reaches `main` through a pull request with a passing build, and milestones are tagged on `main` (for example `v0.1-sprint-0`).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## License

Not decided yet. Until a license is added, all rights are reserved.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Contact

Chathura Liyanage · Senior Software Engineer, Galle, Sri Lanka · [@CHATHURALIYANAGE1997](https://github.com/CHATHURALIYANAGE1997)

Project link: [https://github.com/CHATHURALIYANAGE1997/BusLinkLK](https://github.com/CHATHURALIYANAGE1997/BusLinkLK)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Acknowledgments

* [OpenStreetMap](https://www.openstreetmap.org/) contributors, for the route and road data
* [Leaflet](https://leafletjs.com/), for making the live map easy
* [Confluent's Kafka Streams docs](https://docs.confluent.io/platform/current/streams/), which I'll be reading a lot
* *Designing Data-Intensive Applications* by Martin Kleppmann, for most of the ideas behind the hard parts
* [Best-README-Template](https://github.com/othneildrew/Best-README-Template), for the layout of this file

<p align="right">(<a href="#readme-top">back to top</a>)</p>

[ci-shield]: https://github.com/CHATHURALIYANAGE1997/BusLinkLK/actions/workflows/ci.yml/badge.svg?branch=main
[ci-url]: https://github.com/CHATHURALIYANAGE1997/BusLinkLK/actions/workflows/ci.yml
[jira-url]: https://chathurabimalka.atlassian.net/jira/software/projects/SCRUM/boards/1
[issues-url]: https://github.com/CHATHURALIYANAGE1997/BusLinkLK/issues
[status-shield]: https://img.shields.io/badge/status-in%20development-orange?style=for-the-badge
[sprint-shield]: https://img.shields.io/badge/sprint-0%20foundation-blue?style=for-the-badge
[java-shield]: https://img.shields.io/badge/Java_21-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white
[java-url]: https://openjdk.org/projects/jdk/21/
[spring-shield]: https://img.shields.io/badge/Spring_Boot_4-6DB33F?style=for-the-badge&logo=springboot&logoColor=white
[spring-url]: https://spring.io/projects/spring-boot
[kafka-shield]: https://img.shields.io/badge/Apache_Kafka-231F20?style=for-the-badge&logo=apachekafka&logoColor=white
[kafka-url]: https://kafka.apache.org/
[postgres-shield]: https://img.shields.io/badge/PostgreSQL_+_PostGIS-4169E1?style=for-the-badge&logo=postgresql&logoColor=white
[postgres-url]: https://postgis.net/
[redis-shield]: https://img.shields.io/badge/Redis-DC382D?style=for-the-badge&logo=redis&logoColor=white
[redis-url]: https://redis.io/
[keycloak-shield]: https://img.shields.io/badge/Keycloak-4D4D4D?style=for-the-badge&logo=keycloak&logoColor=white
[keycloak-url]: https://www.keycloak.org/
[docker-shield]: https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white
[docker-url]: https://www.docker.com/
[k8s-shield]: https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white
[k8s-url]: https://kubernetes.io/
[grafana-shield]: https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white
[grafana-url]: https://grafana.com/
[leaflet-shield]: https://img.shields.io/badge/Leaflet-199900?style=for-the-badge&logo=leaflet&logoColor=white
[leaflet-url]: https://leafletjs.com/
