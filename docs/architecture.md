# HelloDATA BE — Architecture Frame

This page is the entry point to the architecture frame of the HelloDATA BE repository: a small, code-anchored set of chapters that describes how the system is actually built — its context, tenancy model, module boundaries, identity flow, state ownership, messaging surface and the decisions behind them — with every claim traceable to a module, class or configuration key that exists in this repository. It is an index, not a chapter: each section below gives a short summary and points at the full chapter under [`docs/arc42/`](arc42/01-context-and-overview.md). It deliberately does not restate the conceptual and operational product documentation under `docs/docs/`, which remains authoritative for what HelloDATA is and how it is operated.

## How to read this document

Read top to bottom once to get the shape of the system, then jump to the chapter you need. The eight sections below follow the epic's topic letters (a)–(h) and map one-to-one onto the arc42 chapters `01`–`07`, plus the spec-chapter index in (h). If you only need to know **who owns what**, the [Ownership at a glance](#ownership-at-a-glance) table answers that from this page alone, without opening a chapter or the code. Anything marked **(planned)** does not exist in the repository yet and is named as a path rather than linked, so no link on this page is broken. Where a topic belongs to a neighbouring epic — the analytics tool internals, or the role catalogue — this page says so and links out rather than duplicating; see [Neighbouring documents](#neighbouring-documents).

---

## (a) Context and system overview

The portal API is the control plane: users reach it through the Angular SPA, Keycloak issues the tokens it validates, PostgreSQL and Redis hold its state and caches, and NATS JetStream is the only channel between the portal and the subsystem sidecars that drive Superset, Airflow and dbt docs. The chapter carries the system-context diagram, the namespace boundaries as the deployment model draws them, and a table of every external system with the protocol and the repository class or module that talks to it. It also states the boundary of the frame itself: the repository contains no Kubernetes API client, so anything namespace-level is deployment-time configuration rather than code.

→ [01 — Context and Overview](arc42/01-context-and-overview.md)

## (b) Tenancy model

Tenancy is `Business Domain → Kubernetes namespace → portal tenant → 1..n Data Domains`, and exactly one business domain is served per portal deployment. The chapter shows how that model materialises in code: the pipe-delimited `hello-data.business-context` / `hello-data.contexts` grammar bound by `HelloDataContextConfig`, the `context` table behind `HdContextEntity` / `HdContextRepository`, and the startup seeding done by `ContextsInitializer` with `ON CONFLICT (context_key) DO NOTHING`. It also fixes the central rule that domain provisioning is **static** — configuration-driven, resolved at startup, with no runtime create or delete path — and closes with a term → property → entity → owner table.

→ [02 — Tenancy Model](arc42/02-tenancy-model.md)

## (c) Module and layer breakdown

The root `pom.xml` aggregates five modules — `hello-data-commons`, `hello-data-portal`, `hello-data-sidecars`, `hello-data-subsystems`, `hello-data-deployment` — and the commons modules form a layered stack of rings that may only reach inwards. The chapter names each ring's package, what belongs in it and what must never be placed there, then states the allowed dependency direction per module with the evidence for each rule. Two consequences are called out on their own: the portal and a sidecar never share a Maven dependency edge, and a change to `hello-data-sidecar-common` is a wire-format change. It ends with a "where do I put a new X?" list that answers the placement question for endpoints, entities, events, permissions and integrations.

→ [03 — Module Breakdown](arc42/03-module-breakdown.md)

## (d) Identity and authorization flow

A request becomes an identity in one place: `SecurityConfig` wires the OAuth2 resource server and hands every JWT to `HellodataAuthenticationConverter`, which resolves the portal user, optionally auto-provisions, and returns a `HellodataAuthenticationToken` whose granted authorities *are* the permission names. The chapter walks that flow end to end, documents the token shape, the `SecurityUtils` accessors, and the converter's two Caffeine caches with their invalidation contract. It states the default-deny principle as three layers that must all hold — `anyRequest().authenticated()`, `@PreAuthorize` per method, and context scoping at the data layer — and lists the endpoints where the second layer is not yet met. The role *catalogue* is explicitly out of scope and belongs to the neighbouring role/authorization epic.

→ [04 — Identity and Authorization](arc42/04-identity-and-authorization.md)

## (e) State ownership rules

For any piece of state, exactly one store owns it: PostgreSQL (`hd_metainfo`) is the system of record, Redis holds derived recomputable aggregates only, NATS JetStream is transport and never a store, and the converter's Caffeine caches are per-replica heap. The chapter gives the rules table, the paths in and out of each cache, and the two corollaries that follow — every write commits in Postgres before anything else is told about it, and losing any store other than Postgres costs time, not data. Its acceptance test is operational: a full `FLUSHALL` against the portal's Redis must be harmless, with recompute latency as the whole worst case. It closes with the Postgres advisory-lock mechanism that keeps multi-replica startup rebuilds from stampeding.

→ [05 — State Ownership](arc42/05-state-ownership.md)

## (f) Messaging taxonomy

Portal and sidecars share no Maven dependency edge and no HTTP endpoint — everything they exchange crosses NATS, and this chapter is the map of that surface. It covers the three enums that are the entire naming vocabulary (`HDEvent`, `HDStream`, `RequestReplySubject`), the `hello-data-nats-spring` publish/subscribe plumbing and its failure behaviour, and the payload contracts that live in `hello-data-sidecar-common`. Two delivery rules bind every participant: **at-least-once**, so each handler must be idempotent, and **publish-after-commit**, so no event may be emitted from inside an uncommitted transaction. An evidenced event map lists every publisher/subscriber pair actually present in the repository, including the rows that have no counterpart, plus the ten rules for adding a new message.

→ [06 — Messaging Taxonomy](arc42/06-messaging-taxonomy.md)

## (g) Architecture decision records

Chapters 01–06 describe what the code does; this chapter records why it does it that way. Six accepted records cover static domain provisioning, the domain switcher as a view filter rather than an authorization boundary, auto-provisioning defaulting to off, the harmless-Redis-flush rule, Postgres advisory locks over a distributed lock manager, and the seeded default admin as a local/bootstrap-only path. Each carries Context, Decision, Alternatives considered and Consequences, with a permanent id that older commits and chapters can point at. Note one open follow-up recorded in the chapter itself: chapters 02, 04, 05 and 06 still contain placeholder links to a planned `09-architecture-decisions.md`, and repointing them at this file is a documentation task, not a decision change.

→ [07 — Decision Records](arc42/07-decision-records.md)

## (h) Links to the docs/spec chapters

Every arc42 chapter ends with a "Related spec chapters" section naming the normative specification it expects to be written against. **The `docs/spec/` tree does not exist in this repository today**, so nothing in it is linked from this page — the paths below are listed as text, under the Planned heading, precisely so that no broken link is emitted. Until those files land, the arc42 chapters are the authoritative statement of each contract, and the per-chapter spec lists are the backlog of what a spec would have to say. When a spec chapter is added, replace its entry here with a relative link and drop it from Planned.

### Planned

The following are **(planned)** and do not exist yet:

| Planned path | Intended content |
| --- | --- |
| `docs/spec/01-authentication-and-authorization.md` | Normative contract for `SecurityConfig`, `HellodataAuthenticationConverter`, consumed token claims, and the per-endpoint `@PreAuthorize` / per-`contextKey` scoping matrix. |
| `docs/spec/02-event-contracts.md` | Per-event contract: `HDEvent` subject strings, payload schemas under `resources/v1/**`, the additive-change rule, and the idempotency obligation per subscriber. |
| `docs/spec/03-portal-persistence.md` | Authoritative table list, Liquibase changelog ordering, and which tables are portal-owned versus projected from subsystems. |
| `docs/spec/04-sidecar-integration.md` | Per-sidecar publish/consume inventory, request/reply subject composition, and what a sidecar must do so a portal-side rebuild is safe to repeat. |
| `docs/spec/05-configuration-and-deployment.md` | Required `hello-data.*` and `spring.*` keys per module, their environment-variable forms, and the per-environment override rules. |

Also **(planned)** and referenced from the chapters: `docs/arc42/09-architecture-decisions.md` — superseded in practice by [07 — Decision Records](arc42/07-decision-records.md); the placeholder links in chapters 02, 04, 05 and 06 are the ones still pointing at it.

---

## Ownership at a glance

Which module owns which concern, for a reader who has not opened the repository yet. Paths are repository-relative directories; types are named without their package where the chapter already carries the fully qualified name.

| Concern | Owning module(s) | Key types / entry points | Full chapter |
| --- | --- | --- | --- |
| **Tenancy** — business/data domains, context keys, context scoping of roles | `hello-data-commons/hello-data-metainfo-model` and `hello-data-commons/hello-data-sidecar-common` (context types), seeded by `hello-data-portal/hello-data-portal-api` | `HdContextEntity`, `HdContextRepository`; `HelloDataContextConfig`, `HdContext`, `HdContextType`, `HdBusinessContextInfo`, `HdRoleName`; `ContextsInitializer` | [02](arc42/02-tenancy-model.md) |
| **Identity** — authentication, token shape, permission resolution, method security | `hello-data-commons/hello-data-common` (`security` package) plus `hello-data-portal/hello-data-portal-api` (`portal/base/auth`, `portal/base/config`) | `Permission`, `HellodataAuthenticationToken`, `SecurityUtils`; `HellodataAuthenticationConverter`; `SecurityConfig` | [04](arc42/04-identity-and-authorization.md) |
| **Persistence** — entities, repositories, audit columns, system of record | `hello-data-commons/hello-data-base-model` and `hello-data-commons/hello-data-portal-common`, on PostgreSQL (`hd_metainfo`) | `BaseEntity`, `Trackable`, `TrackedEntityListener`; `user`, `role`, `query`, `monitoring`, `dashboard_access` entity/repository packages | [05](arc42/05-state-ownership.md) |
| **Messaging** — JetStream plumbing, event vocabulary, wire payloads | `hello-data-commons/hello-data-nats-spring` (transport) and `hello-data-commons/hello-data-sidecar-common` (event and payload types) | `NatsConfiguration`, `NatsSenderService`, `@EnableJetStream`, `@JetStreamSubscribe`, `NatsStreamUtil`; `HDEvent`, `HDStream`, `RequestReplySubject`, `HdResource` and its subtypes | [06](arc42/06-messaging-taxonomy.md) |
| **Deployment** — packaging of the built artefacts for local and demo environments | `hello-data-deployment/*` | `hello-data-dc-portal`, `-keycloak`, `-postgres`, `-superset`, `-airflow`, `-cloudbeaver`, `hello-data-showcase` | [03 — Deployment module](arc42/03-module-breakdown.md#deployment-module) |

Two boundaries worth carrying away from the table. First, **tenancy, identity, persistence and messaging types all live in `hello-data-commons`, never in an application module** — the portal and the sidecars consume them and add behaviour, but neither defines them. Second, **`hello-data-deployment/*` packages artefacts and owns no source of any module**; the authoritative deployment view is [Infrastructure](docs/architecture/infrastructure.md), and no Kubernetes manifests or Kubernetes API client exist in this repository.

## Neighbouring documents

This frame **links to these documents and does not duplicate them.** They remain authoritative for their subject; where a chapter here touches one, it points at where in the code the concept is realised rather than restating the concept.

- [Architecture](docs/architecture/architecture.md) — the business/data domain model, module view, NATS and Keycloak concepts, and building block view of the platform.
- [Data stack](docs/architecture/data-stack.md) — the dbt / Airflow / Superset stack and how the data layers relate.
- [Infrastructure](docs/architecture/infrastructure.md) — Kubernetes namespaces, storage, deployment platforms and K8s jobs.
- [Roles / Authorization Concept](docs/manuals/role-authorization-concept.md) — the role catalogue and what each role is allowed to do.

Two areas belong to **neighbouring epics** and are deliberately absent here:

- **Analytics tool internals — Superset, Airflow and dbt.** How dashboards, DAGs and lineage models are built, layered and operated is covered by [Data stack](docs/architecture/data-stack.md) and the concept pages under `docs/docs/concepts/`. This frame describes only the boundary: which sidecar owns which tool, what it publishes, and what it consumes.
- **The role catalogue.** Which roles exist, what each grants, and how business- and data-domain scoping interact are owned by the role/authorization epic and documented in [Roles / Authorization Concept](docs/manuals/role-authorization-concept.md). [04 — Identity and Authorization](arc42/04-identity-and-authorization.md) treats a permission as an opaque string that must arrive intact at a `@PreAuthorize` expression, and says so explicitly in its scope table.