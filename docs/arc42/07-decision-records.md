# 07 — Decision Records

Chapter (g) of the architecture frame. Chapter (a) is [01 — Context and Overview](./01-context-and-overview.md), chapter (b) is
[02 — Tenancy Model](./02-tenancy-model.md), chapter (c) is [03 — Module Breakdown](./03-module-breakdown.md), chapter (d) is
[04 — Identity and Authorization](./04-identity-and-authorization.md), chapter (e) is [05 — State Ownership](./05-state-ownership.md),
chapter (f) is [06 — Messaging Taxonomy](./06-messaging-taxonomy.md).

Chapters 01–06 describe **what the code does**. This chapter records **why it does it that way**: the six decisions of this epic, each
with the alternatives that were rejected and the consequences the rest of the frame then has to live with. An ADR is not a description
of a class — it is the reason a class looks the way it does, written down so the next change either follows the decision or knowingly
supersedes it.

Everything named below exists in the repository; anything that does not is marked **(planned)**. No credential, key or token value
appears anywhere in this chapter — configuration is referenced by property name only.

## Numbering note

Chapters [02](./02-tenancy-model.md), [04](./04-identity-and-authorization.md), [05](./05-state-ownership.md) and
[06](./06-messaging-taxonomy.md) each contain a placeholder link to `./09-architecture-decisions.md` — **(planned)**. **This file is
that chapter.** The ADR chapter landed as `07-decision-records.md`, in the (g) slot of the frame, rather than as `09-…`. Repointing
those four placeholder links at this file is a documentation follow-up; this ticket adds this chapter only and changes no other file.

Where a placeholder says "the decision is to be recorded there", the corresponding record is:

| Placeholder in | Subject | Record here |
| --- | --- | --- |
| [02 — Tenancy Model](./02-tenancy-model.md), section "Domain provisioning is static" | static, configuration-driven domain provisioning | [ADR-001](#adr-001--domains-are-provisioned-statically-from-configuration) |
| [04 — Identity and Authorization](./04-identity-and-authorization.md), section "The seeded local admin" | seeded-admin bootstrap | [ADR-006](#adr-006--the-seeded-default-admin-is-a-localbootstrap-only-path) |
| [05 — State Ownership](./05-state-ownership.md), section "Decisions recorded elsewhere" | Redis as disposable cache; advisory locks over a distributed lock manager | [ADR-004](#adr-004--a-full-redis-flush-must-be-harmless), [ADR-005](#adr-005--startup-and-shared-recurring-work-is-guarded-by-postgres-advisory-locks) |
| [06 — Messaging Taxonomy](./06-messaging-taxonomy.md), scope table | why NATS at all | **(planned)** — not part of this epic; no record below claims it |

## Index

| Id | Title | Status | Constrains |
| --- | --- | --- | --- |
| [ADR-001](#adr-001--domains-are-provisioned-statically-from-configuration) | Domains are provisioned statically from configuration | Accepted | [02](./02-tenancy-model.md), [01](./01-context-and-overview.md) |
| [ADR-002](#adr-002--the-domain-switcher-is-a-view-filter-not-an-authorization-boundary) | The domain switcher is a view filter, not an authorization boundary | Accepted | [04](./04-identity-and-authorization.md), [02](./02-tenancy-model.md) |
| [ADR-003](#adr-003--auto-provisioning-of-viewers-on-login-defaults-to-off) | Auto-provisioning of viewers on login defaults to OFF | Accepted | [04](./04-identity-and-authorization.md) |
| [ADR-004](#adr-004--a-full-redis-flush-must-be-harmless) | A full Redis flush must be harmless | Accepted | [05](./05-state-ownership.md), [06](./06-messaging-taxonomy.md) |
| [ADR-005](#adr-005--startup-and-shared-recurring-work-is-guarded-by-postgres-advisory-locks) | Startup and shared recurring work is guarded by Postgres advisory locks | Accepted | [05](./05-state-ownership.md), [06](./06-messaging-taxonomy.md) |
| [ADR-006](#adr-006--the-seeded-default-admin-is-a-localbootstrap-only-path) | The seeded default admin is a local/bootstrap-only path | Accepted | [04](./04-identity-and-authorization.md), [03](./03-module-breakdown.md) |

**Format.** Every record has a stable id, a title, a status line, and the four headings **Context**, **Decision**,
**Alternatives considered** and **Consequences**. Ids are permanent: a decision that stops being true is marked *Superseded by
ADR-nnn* and kept, never renumbered and never deleted — the id is what older commits, chapters and review comments point at.

---

## ADR-001 — Domains are provisioned statically from configuration

**Status:** Accepted (recorded 2026-08-25) · constrains [02 — Tenancy Model](./02-tenancy-model.md) and
[01 — Context and Overview](./01-context-and-overview.md).

### Context

The tenancy model is `Business Domain → Kubernetes namespace → portal tenant → 1..n Data Domains`
([02 — Tenancy Model](./02-tenancy-model.md)). A "domain" is not only a row in the portal database: each data domain corresponds to a
deployed Superset / Airflow / dbt-docs instance with its own sidecar, its own `hello-data.*` configuration and its own storage. The
portal is one participant in that arrangement, not its owner — and the repository contains **no Kubernetes API client**, so the portal
cannot create the infrastructure a new domain would need.

The domain identity also has to agree across processes that are deployed and restarted independently. Every sidecar parses the same
pipe-delimited grammar through `ch.bedag.dap.hellodata.commons.sidecars.context.HelloDataContextConfig`
(`@ConfigurationProperties("hello-data")`, `@Validated`), and echoes its own business/data context back to the portal on every
`AppInfoResource`. If the portal could mint a context key at runtime, the portal and the sidecars would disagree about what exists
until someone reconfigured and redeployed the sidecars anyway.

### Decision

**Business and data domains come from configuration and are materialized once at startup. Nothing creates a domain at runtime.**

- `hello-data.business-context` (a single `@NotNull` string, `type | key | name`) and `hello-data.contexts` (a `List<String>`, each
  `type | key | name` with an optional fourth `extra` part) are the only sources.
- `HelloDataContextConfig.validateProperties()` is `@PostConstruct`: exactly 3 parts for the business context, 3 or 4 per context,
  `IllegalArgumentException` naming the offending string otherwise. Misconfiguration fails the context at startup, not on first use.
- `ch.bedag.dap.hellodata.portal.initialize.service.ContextsInitializer.initContexts()` — called **first** by the `Initializer`
  `CommandLineRunner`, in `Propagation.REQUIRES_NEW` — writes the business domain and each configured context with a native
  `INSERT INTO context (...) VALUES (...) ON CONFLICT (context_key) DO NOTHING`, `created_by`/`modified_by` = `'system'`.
- The only other writer is `ch.bedag.dap.hellodata.sidecars.portal.service.context.HdContextService.saveBusinessContext(...)` in
  `hello-data-sidecar-portal`, reacting to an `AppInfoResource` — and that is still static configuration, echoed by the sidecar. It
  fills in `parent_key` and `extra`, which `ContextsInitializer` deliberately does not set.
- At request time, domains are always read back through `HdContextRepository` (`getByContextKey`, `findAllByTypeIn`, …), never
  re-parsed from configuration. `HdContextEntity.contextKey` is a `@NaturalId` and is the join key everywhere else.

Adding a data domain therefore means: change configuration, deploy the subsystem and its sidecar, restart. Removing one is not
implemented at all.

### Alternatives considered

- **A runtime domain-management API** (`POST /contexts`, an admin screen, delete support) — **rejected.** The portal cannot provision
  the Superset/Airflow/dbt instances, namespaces or storage that a domain implies, so the API would create a row describing
  infrastructure that does not exist. Every consumer (`RoleService`, the menu, dashboards) would then have to tolerate a
  half-materialised domain. It also splits ownership: configuration and API could disagree on the next restart, with no reconciler.
- **Deriving domains implicitly from published `AppInfoResource` events** — i.e. a domain exists because a sidecar said so —
  **rejected** as the *primary* source. It makes the tenant's shape depend on which sidecars happen to be up, so a NATS outage or a
  slow sidecar would look like a domain disappearing; and it gives any process that can publish to the stream the ability to define
  tenancy. It is kept only as the secondary, additive path that supplies `parent_key`, which is exactly the part the portal cannot
  know from its own configuration.
- **A dedicated tenancy service or a `contexts` table managed by an external control plane** — **rejected** as unjustified scope: one
  deployment serves exactly one business domain, so there is no cross-tenant registry to keep, and a second system of record would
  contradict [ADR-004](#adr-004--a-full-redis-flush-must-be-harmless)'s single-owner rule.

### Consequences

- **The context table is effectively immutable within a process lifetime.** Code may cache a domain list for the life of a request
  without worrying about concurrent creation, and `RolesInitializer.initContextRoles()` may legitimately block
  (`ContextsNotFetchedYetException`, retried in a loop) until the table is non-empty.
- **Seeding is idempotent and additive.** `ON CONFLICT (context_key) DO NOTHING` in both writers means a restart, a rolling deploy or
  two replicas booting at once converge on the same rows — see [ADR-005](#adr-005--startup-and-shared-recurring-work-is-guarded-by-postgres-advisory-locks)
  for why that idempotency, not a lock, is what makes concurrent startup safe.
- **Onboarding a domain is a deployment, not a click.** That is a deliberate cost: it keeps the portal's view and the deployed
  subsystems in step. Anyone proposing self-service domain creation is proposing to supersede this record, not to extend it.
- **Removal is unimplemented.** A domain dropped from `hello-data.contexts` leaves its `context` row, its `user_context_role` rows and
  its `resource` rows behind. Cleanup is a manual/database operation today; an automated retirement path is **(planned)**.
- **`HdContextType.MODULE` is declared but never persisted** — module-level contexts remain **(planned)**, and no code should assume
  they can appear.

---

## ADR-002 — The domain switcher is a view filter, not an authorization boundary

**Status:** Accepted (recorded 2026-08-25) · constrains [04 — Identity and Authorization](./04-identity-and-authorization.md) and
[02 — Tenancy Model](./02-tenancy-model.md).

### Context

The portal header carries a data-domain switcher. In `hello-data-portal-ui`,
`shared/components/header/header.component.ts` builds its menu from the `selectAvailableDataDomains` selector and dispatches
`setSelectedDataDomain({dataDomain})`; the reducer in `store/my-dashboards/my-dashboards.reducer.ts` writes the choice to
**`localStorage`** under `SELECTED_DATA_DOMAIN_KEY` and keeps it in NgRx state. Downstream selectors — `my-dashboards.selector.ts`,
`faq.selector.ts`, `lineage-docs.selector.ts`, `external-dashboards.selector.ts`, `summary.selector.ts`, `start-page.selector.ts` and
`store/menu/menu.service.ts` — then filter **already-fetched** data by `selectedDataDomain.key` / `.id`, with the synthetic
"all domains" entry (`id: ''`) meaning "do not filter".

Two properties of that mechanism decide everything below. First, its state lives in the browser: `localStorage` is fully under the
user's control and survives logout. Second, it is not transmitted — there is no "current context" header or cookie on the wire, and
the API has no ambient notion of "the domain I am currently in". Endpoints that need a context take one **explicitly**
(`DashboardCommentController` at `/dashboards/{contextKey}/{dashboardId}/comments`, `DomainCommentsController` at
`/domain/{contextKey}`, `DashboardGroupController` with `@RequestParam String contextKey`, `SupersetController` at
`/upload-dashboards/{contextKey}` and `/queries/{contextKey}`).

So the switcher is a *client-side* projection, and every context key that reaches the server is a request parameter — that is, ordinary
untrusted input.

### Decision

**The switcher may be trusted only to shape what the current user sees. It is never an input to an authorization decision, and the
server re-derives the caller's rights on every single request.**

What the switcher **may** be trusted for:

- choosing which of the already-authorised results to render, and which menu entries to show;
- remembering a UI preference across reloads;
- deciding which `contextKey` to *send* on a request that takes one explicitly.

What it **must never** be trusted for:

- proving the user has any role in that domain — the value is attacker-controllable `localStorage`;
- widening a result set: a response must never contain rows the caller could not have obtained with the "all domains" selection;
- standing in for a server-side check on an endpoint that accepts a `contextKey`.

The server-side re-check, on every request, is:

1. **The domain list itself is derived server-side.** `GET /users/data-domains` → `UserService.getAvailableDataDomains()` resolves
   `SecurityUtils.getCurrentUserId()`, returns an empty list when there is no portal user, loads the `UserEntity`, and derives the
   domains from `userEntity.getContextRoles()`. The client never supplies the list it is choosing from.
2. **Identity is rebuilt per request.** `HellodataAuthenticationConverter.convert(Jwt)` runs on every authenticated call and produces a
   fresh `ch.bedag.dap.hellodata.commons.security.HellodataAuthenticationToken` whose granted authorities *are* the permission names
   (`SimpleGrantedAuthority` per permission, no `ROLE_` prefix). Permissions come from Postgres —
   `UserEntity.getPermissionsFromAllRoles()`, or all `Permission` constants for a superuser — never from a JWT claim and never from a
   client field.
3. **Default deny.** `SecurityConfig.filterChain` ends with `auth.anyRequest().authenticated()`, with `AUTH_WHITELIST` limited to
   documentation and actuator paths; `@EnableMethodSecurity` plus `@PreAuthorize("hasAnyAuthority('…')")` gates the endpoints. A caller
   with no portal user gets a token with `userId == null` and an **empty** permission set — authenticated, authorised for nothing.
4. **Downstream code reads identity only through `SecurityUtils`**, which degrades to `null`/empty/`false` rather than throwing, so a
   missing identity fails closed.

### Alternatives considered

- **Send the selected domain as an ambient context header and scope queries by it server-side** — **rejected.** It converts a UI
  preference into a security-relevant request field while looking like a convenience, and it invites the classic failure: a handler
  that filters by the header and therefore appears to enforce something. Explicit `contextKey` parameters on the endpoints that need
  one keep the input visible at the method signature, where a check can be attached to it.
- **Put the selected domain in the JWT (or a server-issued signed cookie) so it is tamper-proof** — **rejected.** It would make every
  domain switch a re-authentication or a token refresh, and it would freeze a security-relevant value for the token's lifetime.
  [04 — Identity and Authorization](./04-identity-and-authorization.md) already shows why the portal does the opposite: even the
  `superuser` flag is deliberately re-read from the database by `UserController.getPermissionsForCurrentUser()` rather than trusted
  from the token.
- **Trust the UI's `PermissionsGuard` / route `requiredPermissions` and skip method security on "UI-only" screens** — **rejected
  outright.** Those exist to hide controls the user cannot use; the API is the only enforcement point. Any endpoint reachable without a
  server-side check is open to every authenticated user of the tenant.
- **Filter results only in the client** (fetch everything, hide the rest) — **rejected** as a security measure. It is acceptable as a
  *rendering* strategy for data the caller is already entitled to, which is precisely what the selectors above do, and nothing more.

### Consequences

- **A tampered `localStorage` value changes nothing but the user's own view.** Selecting a domain the user has no role in yields empty
  or unchanged results, because both the domain list and the payloads were resolved from `getContextRoles()` server-side.
- **Every new endpoint that accepts a `contextKey` owes an authorization check in the same commit** — a `@PreAuthorize` naming a
  `Permission` constant, and, where the operation is domain-scoped, a service-layer check that the caller holds a role on *that*
  `contextKey`. "The UI only sends domains the user can see" is not a check.
- **Known gap, stated plainly.** Several context-taking endpoints today check a *global* permission rather than a per-`contextKey`
  grant: `DashboardCommentController` gates on `DASHBOARDS` (and `DASHBOARD_COMMENTS_IMPORT_EXPORT` for import/export),
  `DashboardGroupController` on a class-level `DASHBOARD_GROUPS_MANAGEMENT`. Per-context enforcement at the method-security layer is
  **(planned)**; until it exists, service-layer scoping is what stands between a permission and cross-domain data. This sits alongside
  the unannotated-controller gaps already listed in [04 — Identity and Authorization](./04-identity-and-authorization.md).
- **Permission changes converge within the converter cache TTL, not instantly**, and per replica — see the caching section of
  [04 — Identity and Authorization](./04-identity-and-authorization.md). Any path that changes roles must call
  `invalidateUserCache(email)`. This is a staleness bound on re-checking, not an exception to it.
- **The switcher can be removed or redesigned freely.** Because no server behaviour depends on it, changing it is a UI decision, not a
  security review.

---

## ADR-003 — Auto-provisioning of viewers on login defaults to OFF

**Status:** Accepted (recorded 2026-08-25) · constrains [04 — Identity and Authorization](./04-identity-and-authorization.md).

### Context

`HellodataAuthenticationConverter.convert(Jwt)` looks the caller up by e-mail, and when no portal user exists calls
`autoProvisionService.autoProvisionIfEnabled(email, givenName, familyName, jwt.getSubject())`.
`ch.bedag.dap.hellodata.portal.user.service.AutoProvisionService` — when enabled — creates the `UserEntity` (id = the Keycloak `sub`,
enabled, federated, non-superuser), sets the business-domain role to `NONE`, assigns `DATA_DOMAIN_VIEWER` across all data domains as
both context roles and `UserPortalRoleEntity` rows, grants every **published** Superset dashboard, publishes `CREATE_USER` over NATS
and a `UserFullSyncEvent` after commit. The full behaviour, its race handling (`Propagation.REQUIRES_NEW` plus a double-check, with
`DataAccessException`/`PersistenceException` caught in the converter) and its first-login UX are documented in
[Auto-provision viewer on login](../docs/concepts/auto-provision-viewer-on-login.md).

The decision to make is not *whether the feature exists* — it does — but **what happens when nobody has configured anything**. The
answer matters because the portal is an OAuth2 resource server in front of a Keycloak realm it does not own. Whoever can obtain a token
from that realm reaches the converter. If provisioning were on by default, the realm's registration policy would silently become the
portal's access policy, in every environment, including ones nobody deliberately opened.

### Decision

**Auto-provisioning is OFF unless explicitly switched on by configuration.**

- The flag is `autoProvisionViewerOnLogin` on
  `ch.bedag.dap.hellodata.portal.base.config.SystemProperties` (`@ConfigurationProperties("hello-data.system-properties")`), i.e. the
  property `hello-data.system-properties.auto-provision-viewer-on-login`, environment form
  `HELLO_DATA_SYSTEM_PROPERTIES_AUTO_PROVISION_VIEWER_ON_LOGIN`.
- It is a `boolean`, so an unset property is `false`, and `hello-data-portal-api/src/main/resources/application.yml` additionally
  states `false` explicitly rather than relying on the primitive default. Both layers say "off"; neither can be misread.
- With the flag off, `autoProvisionIfEnabled(...)` is a no-op returning `null`. The converter still builds a token — with
  `userId == null`, `superuser == false` and an **empty** permission set. The caller is authenticated and authorised for nothing, which
  is the intended default-deny outcome of [ADR-002](#adr-002--the-domain-switcher-is-a-view-filter-not-an-authorization-boundary),
  not an error path.
- Turning it on is a deliberate, environment-scoped act with a documented security consequence: **every** identity the realm will
  authenticate gains portal access and every published dashboard.

### Alternatives considered

- **Default ON, opt out to disable** — **rejected.** It makes the safe configuration the one you have to remember, and it fails open:
  an operator who never reads this property ends up granting read access to the whole realm. Defaulting to deny is the same principle
  that governs `anyRequest().authenticated()` and the empty permission set.
- **No feature at all; every account created by an administrator** — **rejected.** The onboarding cost is real for tenants with large
  read-only populations, and the concept document names exactly those cases (large read-only user bases, dev/test environments) as the
  ones the feature exists for. Removing it would push operators toward worse workarounds, such as a shared account.
- **Provision on login but leave the user with no roles, pending admin approval** — **rejected** for this epic. It creates a queue of
  unusable accounts that must be reconciled with Keycloak, and it still writes a `UserEntity` per authenticated identity, so it carries
  the storage and personal-data cost of provisioning without the benefit. An approval workflow remains **(planned)**.
- **Restrict auto-provisioning by e-mail domain or Keycloak group** — **rejected as a substitute**, not as an idea: it would be a
  refinement *inside* the enabled path, and it does not change what the default must be. Filtering is **(planned)**; the default stays
  off either way.

### Consequences

- **A fresh deployment grants nothing.** The first login of an unknown user produces a token with no authorities; someone with
  `USER_MANAGEMENT` must create the account. That is the intended out-of-the-box behaviour, and support material should say so rather
  than treat it as a misconfiguration.
- **Enabling it is a security decision about the *realm*, not about the portal.** Before switching it on, the realm's registration and
  federation policy must be confirmed — the concept document carries the same warning. Record the decision per environment.
- **The enabled path must stay idempotent under concurrency.** Simultaneous first logins are handled by the `REQUIRES_NEW` transaction,
  the double-check before insert, and the converter's catch-invalidate-re-read. Any change to `AutoProvisionService` must preserve all
  three; the same at-least-once reasoning as [06 — Messaging Taxonomy](./06-messaging-taxonomy.md) applies to the `CREATE_USER` it
  publishes.
- **Provisioned users are ordinary users afterwards.** An administrator can promote, demote or disable them exactly as for a manually
  created account; there is no second class of identity to reason about.
- **The flag does not weaken any check.** An auto-provisioned viewer holds `DATA_DOMAIN_VIEWER` and nothing more, and is subject to the
  same `@PreAuthorize` gates — which is why the unannotated controllers listed in
  [04 — Identity and Authorization](./04-identity-and-authorization.md) matter more once the flag is on: their audience grows from
  "users an admin created" to "everyone the realm authenticates".

---

## ADR-004 — A full Redis flush must be harmless

**Status:** Accepted (recorded 2026-08-25) · constrains [05 — State Ownership](./05-state-ownership.md) and
[06 — Messaging Taxonomy](./06-messaging-taxonomy.md).

### Context

`hello-data-portal-api` depends on `spring-boot-starter-data-redis` and connects via `spring.data.redis.host` / `.port`. The whole of
its Redis usage is the Spring Cache abstraction: `ch.bedag.dap.hellodata.portal.base.config.RedisConfig` is
`@Configuration @EnableCaching` and declares exactly one `cacheManager(RedisConnectionFactory)` bean — a `RedisCacheManager` with
`StringRedisSerializer` keys and a `GenericJacksonJsonRedisSerializer` for values. There is **no `RedisTemplate` anywhere in the
repository**, no Spring Session and no Redis-based lock.

Two caches are configured: `RedisConfig.SUBSYSTEM_USERS_CACHE` → `subsystem_users` and `RedisConfig.USERS_WITH_DASHBOARD_CACHE` →
`users_with_dashboards`, both filled by `MetaInfoUsersService` (`@Cacheable` read-through, `@CachePut` eager refresh) and both
recomputable from Postgres alone. Their TTLs are mandatory `@Value` bindings —
`hello-data.cache.subsystem-users-ttl-minutes` and `hello-data.cache.users-with-dashboards-ttl-minutes` — so a missing property fails
startup rather than caching forever.

Redis in a Kubernetes deployment is a component that gets restarted, resized, evicted and replaced. The question this record settles is
what the rest of the system is allowed to assume about it.

### Decision

**Redis holds derived cache only — never a system of record — and the acceptance test for that claim is operational: an operator may
run `FLUSHALL` against the portal's Redis at any moment, in production, without warning, and the only permitted effect is latency.**

Concretely:

- **Everything in Redis arrives through `@Cacheable` / `@CachePut` and can be removed by `@CacheEvict` or a flush.** Introducing a
  direct `RedisTemplate` write is the specific move this record forbids, because it creates a fact whose only copy is in a cache.
- **Postgres commits first; the cache and the event only announce.** `PublishedUserResourcesConsumer` persists the incoming
  `UserResource` and *then* publishes `UPDATE_METAINFO_USERS_CACHE`; `CacheUpdateService` responds by recomputing from Postgres. The
  event is a hint to recompute, never a carrier of the value — the same publish-after-commit rule as
  [06 — Messaging Taxonomy](./06-messaging-taxonomy.md).
- **No cache hit is authoritative for authorization or persistence.** `@PreAuthorize` on `MetaInfoResourceController` — including both
  `clear-cache` endpoints — is evaluated from the request's authorities, which came from Postgres via the converter. A missing cache
  entry means "not computed yet", never "denied".
- **A new cache needs a named rebuild path.** If you cannot point at the method that recomputes it from Postgres, it is not a cache; it
  is unbacked state and it does not belong in Redis.

After a flush, the required outcome is: the next read recomputes and is slower. The forbidden outcomes are: a lost role, dashboard
assignment or comment; a reverted permission change; a request that would have been rejected now being allowed; a 500 because an entry
was missing.

### Alternatives considered

- **Use Redis as a shared data grid / session store** — hold HTTP sessions, or authoritative aggregates, in Redis — **rejected.** It
  would make Redis a second system of record with no backup story, no Liquibase-reviewed schema and no recovery path, and it would make
  a routine cache flush a data-loss event. It would also contradict the single-owner rule that the rest of
  [05 — State Ownership](./05-state-ownership.md) is built on.
- **Cache the authorization decision** (permissions or the superuser flag) **in Redis** — **rejected.** Staleness would then change a
  security outcome across replicas, with no bounded invalidation path. The portal deliberately does the opposite: the converter's
  Caffeine caches are per-JVM with explicit `invalidateUserCache(...)` calls, and
  `UserController.getPermissionsForCurrentUser()` re-reads the superuser flag from the database precisely because a cached value is not
  good enough for a security answer.
- **Drop Redis entirely and always recompute** — **rejected** on cost. `refreshDashboardUsersCache()` reads all Superset app-info and
  dashboard resources, all contexts, all portal users with their business-domain role and every `HELLO_DATA_USERS` resource pack, then
  produces a row per user per Superset instance. For a large tenant that is seconds. The cache exists for exactly that reason — and
  "worst case: recompute latency" is the whole worst case.
- **Persist the cache (RDB/AOF) and treat it as durable** — **rejected.** Durability of a derived value is not the same as ownership of
  a fact, and relying on it would quietly re-create the "only copy in a cache" failure this record exists to prevent.

### Consequences

- **Redis can be restarted, resized or replaced during a release** with no coordination beyond accepting a slower first request.
- **Recompute cost must be budgeted, not hidden.** The refresh methods log their duration; a flush during peak load is a latency event
  and should be treated as one.
- **Eviction is all-or-nothing today.** Both cached methods take no arguments, so Spring's default key generator yields
  `SimpleKey.EMPTY` and each cache holds exactly one entry — there is no per-user granularity, and a miss costs a full tenant-wide
  recompute. The two `clear-cache` endpoints evict that same default key, which works today; if either cached method ever gains a
  parameter, the key changes and the evict silently stops matching — add `allEntries = true` at that point.
- **"A flush is harmless" is a statement about data, not availability.** The `cacheManager` bean requires a `RedisConnectionFactory`,
  so Redis is a hard dependency at startup and an outage is still an outage. Making it optional with a `ConcurrentMapCacheManager`
  fallback is a code change and out of scope here.
- **Two cache-clearing endpoints are `GET`s.** Harmless under this record — the worst outcome of an accidental call is a recompute —
  but that reasoning is what makes them acceptable, so it stops applying to any future endpoint that does more than drop a cache.

---

## ADR-005 — Startup and shared recurring work is guarded by Postgres advisory locks

**Status:** Accepted (recorded 2026-08-25) · constrains [05 — State Ownership](./05-state-ownership.md) and
[06 — Messaging Taxonomy](./06-messaging-taxonomy.md).

### Context

`hello-data-portal-api` runs as more than one replica, and several pieces of work are *shared*: they rebuild state that all replicas
read. The user synchronisation sweep (`@Scheduled` every 30 s) and the metainfo users cache rebuild (driven by the
`UPDATE_METAINFO_USERS_CACHE` event) both fire on every replica, so without coordination a rolling deploy means N replicas doing the
same expensive rebuild simultaneously — and, worse, interleaving with each other.

Recompute-on-demand ([ADR-004](#adr-004--a-full-redis-flush-must-be-harmless)) is only affordable if that stampede is prevented. The
constraint on the mechanism is that it must not introduce a second system to keep alive: the portal already depends on Postgres for
every fact it owns, and adding a distributed lock manager would mean an availability dependency that can fail *independently* of the
data it protects.

### Decision

**Coordination uses PostgreSQL advisory locks, through `ch.bedag.dap.hellodata.portal.lock.service.AdvisoryLockService` — the same
store that owns the data also owns the coordination — and every guarded job releases stale locks at startup so replicas can boot
concurrently.**

`AdvisoryLockService` is a thin `JdbcTemplate` wrapper, both statements parameterised, never concatenated:

- `acquireLock(long lockId)` → `SELECT pg_try_advisory_lock(?)` — non-blocking, `false` if another session holds it;
- `releaseStaleLock(long lockId)` → `SELECT pg_advisory_unlock(?)`.

Two callers, each with its own id, each releasing on startup:

| Caller | Lock id | Startup hook | Guarded work |
| --- | --- | --- | --- |
| `ch.bedag.dap.hellodata.portal.sync.service.UsersSyncService` | `5432543124` | `@PostConstruct releaseStaleLocksOnStartup()` | `synchronizeUsers()` (`@Scheduled` fixedDelay 30 s) and the 15-minute `resetStatusIfOld()` sweep over `UserSyncLockEntity` |
| `ch.bedag.dap.hellodata.portal.cache.service.CacheUpdateService` | `6432543124` | `@PostConstruct releaseStaleLocksOnStartup()` | `updateMetainfoUsersCache(UserCacheUpdate)` — the `subsystem_users` / `users_with_dashboards` rebuild |

The shape is identical in both: try the lock, do the work in a `try`, release in the matching `finally`; if the lock is not obtained,
log at `debug` ("Another instance is already synchronizing…") and return. **Losing the race is a no-op, not an error** — the other
replica is already doing the work and the result lands in a store both replicas read.

The `@PostConstruct` release is the defensive half. Advisory locks are session-scoped, so Postgres releases them when a killed
replica's backend session ends; the explicit release at startup is what keeps a half-finished rebuild from wedging the next scheduled
run, so a rolling restart or a crash-loop converges instead of deadlocking.

Startup *seeding* is coordinated differently and deliberately: `Initializer` (the `CommandLineRunner`) is **not** lock-guarded.
`ContextsInitializer` uses `ON CONFLICT (context_key) DO NOTHING` and `DefaultUserInitializer` checks the `default_user` marker row and
Keycloak before acting, so concurrent boots are safe by **idempotency** rather than by mutual exclusion
([ADR-001](#adr-001--domains-are-provisioned-statically-from-configuration),
[ADR-006](#adr-006--the-seeded-default-admin-is-a-localbootstrap-only-path)).

### Alternatives considered

- **A distributed lock manager (Redis `SETNX`/Redlock, ZooKeeper, etcd)** — **rejected.** Redis in this deployment is a disposable
  cache that an operator may flush at will ([ADR-004](#adr-004--a-full-redis-flush-must-be-harmless)); a lock living there could vanish
  mid-job. ZooKeeper or etcd would add a component to operate, monitor and upgrade, and an availability dependency separate from the
  data being protected. Postgres is already a hard dependency: if it is down, there is no work to coordinate.
- **A lock row in a table with `SELECT … FOR UPDATE` or a status column** — **partially rejected.** `UserSyncLockEntity` still exists
  and carries the *business* status (`STARTED` / `COMPLETED`) with the 15-minute staleness sweep, which is the right tool for "is a
  sync in progress". As a *mutual-exclusion* primitive a row lock is worse: it holds a row lock for the duration of the job and needs
  explicit crash cleanup, whereas an advisory lock is released by the database when the session dies.
- **Elect a leader replica and run all scheduled work only there** — **rejected** as disproportionate. It needs its own election
  protocol and failover semantics to protect two jobs, and it would make an ordinary replica restart a leadership event.
- **Do nothing and let every replica rebuild** — **rejected.** Both jobs are tenant-wide recomputes; N replicas doing them at once
  multiplies database load exactly when a deploy is already stressing the system.

### Consequences

- **Multiple replicas may boot concurrently and simultaneously.** Seeding is idempotent, stale locks are released, and the loser of any
  race simply skips. This is the property that makes rolling deploys safe.
- **Guarded work must stay idempotent.** The lock reduces duplicated effort; it is not a correctness substitute. `updateMetainfoUsersCache`
  is safe to run twice because "handling it" means "recompute from Postgres" — the same reasoning the at-least-once delivery rule in
  [06 — Messaging Taxonomy](./06-messaging-taxonomy.md) demands of every subscriber.
- **Rules for anything new that runs on every replica:** guard it with an `AdvisoryLockService` lock id and release in a `finally`;
  pick a *fresh, distinct* `lockId` constant, since reusing one silently serialises two unrelated jobs; keep lock and work in the same
  transactional boundary so acquire and release use the same connection (`synchronizeUsers()` is `@Transactional`,
  `updateMetainfoUsersCache(...)` inherits `@Transactional` from `@JetStreamSubscribe`).
- **Lock ids are magic numbers with no registry.** `5432543124` and `6432543124` are private constants in two unrelated classes; a
  third job that reuses one would be silently serialised against an unrelated rebuild with no error. A shared constants holder is
  **(planned)** — until it exists, grep both classes before choosing an id.
- **A skipped run is invisible at `INFO`.** Losing the race logs at `debug`. When diagnosing "the sync did not seem to run", that is the
  first log level to raise.
- **`releaseStaleLock` is unconditional.** It unlocks the id regardless of who holds it, which is what makes the `@PostConstruct` sweep
  work; it also means a *new* replica's startup can release a lock a *running* replica holds. Acceptable here only because both guarded
  jobs are idempotent recomputes — do not copy the pattern for work where a duplicate run would not be harmless.

---

## ADR-006 — The seeded default admin is a local/bootstrap-only path

**Status:** Accepted (recorded 2026-08-25) · constrains [04 — Identity and Authorization](./04-identity-and-authorization.md) and
[03 — Module Breakdown](./03-module-breakdown.md).

### Context

A brand-new deployment has a chicken-and-egg problem: creating users requires `USER_MANAGEMENT`, and nobody holds it yet. The portal
resolves this with `ch.bedag.dap.hellodata.portal.initialize.service.DefaultUserInitializer`, invoked from the `Initializer`
`CommandLineRunner` after contexts and roles are seeded. It reads
`ch.bedag.dap.hellodata.portal.user.conf.DefaultAdminProperties` (`@ConfigurationProperties("hello-data.default-admin")`, exposing
`firstName`, `lastName`, `username`, `email`, `password`) and, in `Propagation.REQUIRES_NEW`:

- returns early with a warning when `hello-data.default-admin.email` is unset — *"No default admin properties set, omitting"*;
- reconciles against Keycloak: creates the user through the Keycloak Admin client when absent, otherwise only marks the existing one;
- throws `IllegalStateException` when the configured username and e-mail resolve to **two different** Keycloak users, naming both and
  telling the operator to fix the configuration;
- writes a `DefaultUserEntity` marker row (`updateDefaultUser(...)`) so later runs are idempotent;
- promotes the user via `RoleService.setBusinessDomainRoleForUser(..., HdRoleName.HELLODATA_ADMIN)` and
  `setAllDataDomainRolesForUser(..., HdRoleName.DATA_DOMAIN_ADMIN)`, but only once contexts exist (`contextRepository.count() > 0`).

This creates a fully privileged account from static configuration. That is a bootstrap convenience with an obvious blast radius, so the
decision is about *scope* and *credential handling*, not about whether the mechanism may exist.

### Decision

**The seeded default admin is a local-development and first-boot bootstrap path only. Its credentials come from environment or
configuration, are never hardcoded in code and never committed as real values, and in any shared or production environment
`hello-data.default-admin.*` is either left unset or the resulting account is disabled once a real administrator exists.**

Supporting properties of the design that make this defensible:

- **It is an initialization concern, not an authentication path.** The seeded admin still logs in through Keycloak and is still
  converted by `HellodataAuthenticationConverter` like anyone else. There is no bypass of the filter chain, no back door, no
  password check inside the portal.
- **The password is only ever handed to the Keycloak Admin API at creation time.** `setDefaultAdminPassword(...)` builds a
  `CredentialRepresentation` (type `PASSWORD`, `temporary = false`) attached to the `UserRepresentation` that is sent to Keycloak. The
  portal does not store it, does not persist it on `UserEntity`, and must never log it.
- **Absence is the safe state.** No `email` configured → the initializer logs a warning and does nothing. Nothing is created by
  default.
- **It is idempotent.** The `default_user` marker plus the Keycloak lookup mean re-running startup neither duplicates the account nor
  resets its password, so a restart is not a credential-rotation event in either direction.
- **Conflicting configuration fails loudly**, with an actionable message, instead of silently promoting the wrong account.

The same reasoning applies to the `create-example-users` profile and `hello-data.example-users.*` used by `ExampleUsersInitializer`:
demonstration data, never a production path.

### Alternatives considered

- **Ship a hardcoded admin account in code** — **rejected outright.** A credential in source is a credential in every checkout, every
  build artefact and every mirror, and it cannot be rotated per environment. It also violates the repository's own rule that secrets
  come from environment, configuration or a secret store.
- **Bootstrap by granting `HELLODATA_ADMIN` to the first user who logs in** — **rejected.** It makes the first race winner a superuser,
  and combined with [ADR-003](#adr-003--auto-provisioning-of-viewers-on-login-defaults-to-off) being enabled it would hand the
  privilege to whoever the realm authenticates first. Silent, unauditable, and impossible to undo before it happens.
- **Require the admin to be created out-of-band in Keycloak and mapped manually** — **rejected as the only option**, though it is the
  recommended *production* practice and is exactly what the "already exists → only mark as default" branch supports. As the sole path
  it would make local development and CI setup a multi-step manual chore, which is what drove the initializer's existence.
- **Generate a random password at first boot and print it to the log** — **rejected.** It moves a credential into the log sink, which
  the logging rules of [06 — Messaging Taxonomy](./06-messaging-taxonomy.md) forbid for exactly this class of value, and log
  retention would then outlive the rotation.
- **Auto-disable the account after N days** — **rejected for now** as unverifiable in code and surprising in operation; the operational
  rule ("unset it, or disable the account once a real admin exists") is stated here instead. An automated retirement is **(planned)**.

### Consequences

- **Production deployments must leave `hello-data.default-admin.*` unset**, or disable the seeded account as soon as a real
  administrator holds `HELLODATA_ADMIN`. This is an operational obligation created by this record, and it belongs in the deployment
  checklist, not only here.
- **Values are supplied per environment** through the deployment's configuration mechanism — Kubernetes secrets, environment variables,
  or a secret store — and are referenced in documentation by property name only, as done throughout this chapter.
- **Flag on the current repository state, without quoting anything.** The checked-in
  `hello-data-portal/hello-data-portal-api/src/main/resources/application.yml` carries local-development placeholder values for the
  `hello-data.default-admin.*` properties, and likewise for the Keycloak admin client secret under `hello-data.auth-server.*`. Those
  are development conveniences, not credentials for any real environment: every deployed environment **must** override all of them, and
  no committed value should ever be reachable from a deployment that matters. Treating a committed placeholder as a working credential
  is the failure mode this record exists to prevent. Moving those defaults out of the committed file is a code change and out of scope
  for this document.
- **The seeded admin is auditable.** The `default_user` table records which `UserEntity` was seeded, and `TrackedEntityListener` stamps
  `createdBy`/`modifiedBy` — startup work is attributed to `SYSTEM` via `SecurityUtils.getCurrentUsername()`. "Who made this account an
  admin" has an answer.
- **Never log the password, and never log personal data around this path.** `DefaultUserInitializer` logs e-mails and usernames when it
  reports a username/e-mail conflict; that is the minimum needed to make the error actionable, and it is the ceiling — no credential,
  and no additional personal data, may be added to those statements.

---

## Related spec chapters

The `docs/spec/` tree does not exist in the repository yet — **every** link below is to a **(planned)** chapter and will resolve only
once that chapter is added:

- [Authentication and authorization spec](../spec/01-authentication-and-authorization.md) — **(planned)**; the normative form of [ADR-002](#adr-002--the-domain-switcher-is-a-view-filter-not-an-authorization-boundary), [ADR-003](#adr-003--auto-provisioning-of-viewers-on-login-defaults-to-off) and [ADR-006](#adr-006--the-seeded-default-admin-is-a-localbootstrap-only-path): the per-endpoint `@PreAuthorize` matrix, the per-`contextKey` scoping rule, and the bootstrap-admin checklist.
- [Event contracts spec](../spec/02-event-contracts.md) — **(planned)**; the publish-after-commit and idempotency obligations that [ADR-004](#adr-004--a-full-redis-flush-must-be-harmless) and [ADR-005](#adr-005--startup-and-shared-recurring-work-is-guarded-by-postgres-advisory-locks) depend on.
- [Portal persistence spec](../spec/03-portal-persistence.md) — **(planned)**; the `context`, `user_`, `default_user` and `user_sync_lock` tables behind [ADR-001](#adr-001--domains-are-provisioned-statically-from-configuration), [ADR-005](#adr-005--startup-and-shared-recurring-work-is-guarded-by-postgres-advisory-locks) and [ADR-006](#adr-006--the-seeded-default-admin-is-a-localbootstrap-only-path).
- [Sidecar integration spec](../spec/04-sidecar-integration.md) — **(planned)**; per-sidecar context configuration and the app-info echo that supplies `parent_key` under [ADR-001](#adr-001--domains-are-provisioned-statically-from-configuration).
- [Configuration and deployment spec](../spec/05-configuration-and-deployment.md) — **(planned)**; `hello-data.business-context`, `hello-data.contexts`, `hello-data.system-properties.auto-provision-viewer-on-login`, `hello-data.cache.*`, `spring.data.redis.*`, `hello-data.default-admin.*` and the `create-example-users` profile, with the per-environment override rules this chapter requires.