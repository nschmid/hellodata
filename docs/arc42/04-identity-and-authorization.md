# 04 — Identity and Authorization

Chapter (d) of the architecture frame. Chapter (a) is [01 — Context and Overview](./01-context-and-overview.md), chapter (b)
is [02 — Tenancy Model](./02-tenancy-model.md), chapter (c) is [03 — Module Breakdown](./03-module-breakdown.md).

This chapter describes **how a request becomes an identity** in `hello-data-portal-api`: the Spring Security resource-server
wiring, the conversion of a Keycloak JWT into a HelloDATA-specific authentication token, the shape of that token, how
permissions reach method security, and how the converter's caches are invalidated. Everything named below exists in the
repository; anything that does not is marked **(planned)**. No credential values appear here — configuration is referenced by
property name only.

## Scope: what this chapter owns, and what it does not

| Concern | Owner | Where |
| --- | --- | --- |
| Resource-server filter chain, whitelist, CORS/CSRF/frame options | **this chapter** | `ch.bedag.dap.hellodata.portal.base.config.SecurityConfig` |
| JWT → application token conversion, auto-provision hook on first login | **this chapter** | `ch.bedag.dap.hellodata.portal.base.auth.HellodataAuthenticationConverter` |
| Token shape and its granted authorities | **this chapter** | `ch.bedag.dap.hellodata.commons.security.HellodataAuthenticationToken` |
| Reading the current identity from anywhere in the code | **this chapter** | `ch.bedag.dap.hellodata.commons.security.SecurityUtils` |
| Converter cache lifetime and invalidation | **this chapter** | `invalidateUserCache(String)`, `invalidateAllUserCaches()` |
| Default-deny principle and endpoint-level enforcement | **this chapter** | `@EnableMethodSecurity` + `@PreAuthorize` on controllers |
| The **role catalogue**: which roles exist, what each grants | neighbouring role/authorization epic | `HdRoleName`, `RoleEntity`, `PortalRoleEntity`, `UserContextRoleEntity`, `UserPortalRoleEntity` |
| `Permission` **semantics** — what `DASHBOARDS` or `USER_MANAGEMENT` means functionally | neighbouring role/authorization epic | `ch.bedag.dap.hellodata.commons.security.Permission` |
| Role → permission mapping and context scoping rules | neighbouring role/authorization epic | see [02 — Tenancy Model](./02-tenancy-model.md) for context scoping |
| Seeded local admin bootstrap | initialization concern, recorded as an ADR | `DefaultUserInitializer`, `DefaultAdminProperties` |

The authoritative description of the role catalogue and what each role is allowed to do is
[Roles / Authorization Concept](../docs/manuals/role-authorization-concept.md). This chapter treats a permission as an
**opaque string** that must arrive intact at a `@PreAuthorize` expression; it deliberately does not restate which role yields
which permission. `ch.bedag.dap.hellodata.commons.sidecars.context.role.HdRoleName` and the `*RoleEntity` types are named
here only where the plumbing touches them.

## The flow, end to end

### 1. Keycloak issues the JWT

The Angular SPA performs an OIDC authorization-code login against Keycloak and sends the resulting access token as a
`Bearer` header on every `/api` call. The portal never sees a password on this path. The realm endpoint is derived from
`hello-data.auth-server.url` and `hello-data.auth-server.realm`, which feed
`spring.security.oauth2.resourceserver.jwt.issuer-uri` (and the `oauth2.client` registration used for the login flow).
The portal validates the token as an OAuth2 **resource server**; it does not mint tokens.

Claims the portal relies on: `email`, `given_name`, `family_name`, and `sub` (the Keycloak subject, which is also used as the
portal `UserEntity` id — the comment on `HellodataAuthenticationToken.userId` records that "keycloak and DB id are the same").

### 2. `SecurityConfig.filterChain(HttpSecurity)` wires the chain

`ch.bedag.dap.hellodata.portal.base.config.SecurityConfig` is annotated `@Configuration`, `@EnableWebSecurity` and
`@EnableMethodSecurity` — the last of these is what makes `@PreAuthorize` on controller methods effective. The
`filterChain(HttpSecurity)` bean composes:

- **Frame options** — `configureFrameOptions(...)`: `deny` by default; only the `disable-frame-options` profile relaxes it
  ("backend is not embedded into iframe").
- **CORS** — `configureCors(...)`: active unless the `disable-cors` profile is set. Origins are read from
  `hello-data.cors.allowed-origins` (comma-separated), methods `GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS`, a fixed allowed-header
  list including `Authorization`, `maxAge` 3600, exposed header `xsrf-token`. With an empty origin list it falls back to `*`.
- **CSRF** — `configureCsrf(...)`: enabled with defaults unless the `disable-csrf` profile is set.
- **Authorization** — `auth.requestMatchers(AUTH_WHITELIST).permitAll()` then **`auth.anyRequest().authenticated()`**. The
  whitelist is exactly the Swagger/OpenAPI surface (`/v3/api-docs/**`, `/swagger-ui/**`, the v2 paths, `/webjars/**`), the
  root path `/`, and `/actuator/**`. Paths are relative to the `server.servlet.context-path` of `/api`.
- **Login and logout** — `http.oauth2Login(withDefaults())` and a logout configurer adding `KeycloakLogoutHandler` with
  `logoutSuccessUrl("/")`.
- **Resource server** — `http.oauth2ResourceServer(... .jwt(jwtConfigurer -> jwtConfigurer.jwtAuthenticationConverter(hellodataAuthenticationConverter)))`.
  This single line is the hand-off: **all** JWT-to-authentication conversion is delegated to the HelloDATA converter. The
  field is declared as a raw `Converter` and resolved by bean name, so the bean name `hellodataAuthenticationConverter` is
  load-bearing — renaming the class without renaming the field breaks the wiring.

### 3. `HellodataAuthenticationConverter.convert(Jwt)` builds the token

`ch.bedag.dap.hellodata.portal.base.auth.HellodataAuthenticationConverter` is a `@Component` implementing
`Converter<Jwt, HellodataAuthenticationToken>`. `convert(Jwt)` is `@Transactional` and does the following:

1. Reads `email`, `given_name` and `family_name` from the JWT claims.
2. Looks the user up by e-mail via the cached `getUserDto(email)` (backed by `UserRepository.findUserEntityByEmailIgnoreCase`,
   mapped with `UserDtoMapper`).
3. **If no portal user exists**, calls `autoProvisionService.autoProvisionIfEnabled(email, givenName, familyName, jwt.getSubject())`.
   That service is a no-op unless `hello-data.system-properties.auto-provision-viewer-on-login` is enabled; when enabled it
   creates the `UserEntity` (id = Keycloak subject), assigns viewer roles and dashboards and announces the user over NATS.
   Concurrent provisioning is tolerated: a `DataAccessException`/`PersistenceException` is caught, the cache invalidated, and
   the user re-read. The concept is documented in
   [Auto-provision viewer on login](../docs/concepts/auto-provision-viewer-on-login.md).
4. **Resolves permissions**:
   - superuser (`UserDto.superuser`, derived from `UserEntity.isHelloDataAdmin()`) → **all** `Permission` constants,
     `Arrays.stream(Permission.values()).map(Enum::name)`;
   - otherwise → `getPortalPermissions(email)`, i.e. `UserEntity.getPermissionsFromAllRoles()`, which flattens the
     `portalRoles` of the user into their role's `Permissions.getPortalPermissions()`.
5. Returns `new HellodataAuthenticationToken(userId, givenName, familyName, email, isSuperuser, permissions)`.

If no `UserDto` can be resolved (no portal user and auto-provision disabled), the token is still built — but with
`userId == null`, `superuser == false` and an **empty** permission set. Such a caller is authenticated yet authorised for
nothing, which is the intended default-deny outcome rather than an error.

### 4. `HellodataAuthenticationToken` — the token shape

`ch.bedag.dap.hellodata.commons.security.HellodataAuthenticationToken` lives in `hello-data-common` (ring 0), so it is
visible to every module. It extends `AbstractAuthenticationToken` and is immutable:

| Member | Type | Notes |
| --- | --- | --- |
| `userId` | `UUID` | Keycloak subject and portal DB id are the same value; `null` when no portal user exists |
| `firstname` | `String` | from the `given_name` claim |
| `lastName` | `String` | from the `family_name` claim |
| `email` | `String` | from the `email` claim; also returned by `getPrincipal()` |
| `superuser` | `boolean` | true for a HelloDATA admin; grants the full `Permission` set |
| `permissions` | `Set<String>` | permission names; also mapped into the token's granted authorities |

The constructor calls `super(permissions.stream().map(SimpleGrantedAuthority::new).toList())` and then
`setAuthenticated(true)`. **This is the mechanism that makes `hasAnyAuthority('...')` work**: a permission name *is* an
authority name, one-to-one, with no `ROLE_` prefix and no separate role authority. `getCredentials()` returns `null` — the
token never carries the bearer credential onward.

### 5. `SecurityUtils` — how downstream code reads the identity

`ch.bedag.dap.hellodata.commons.security.SecurityUtils` is a `@UtilityClass` that reads
`SecurityContextHolder.getContext().getAuthentication()` and is the **only** sanctioned way to ask "who is calling?" (54
call sites across 10 classes in `hello-data-portal-api` today). Members:

- `getCurrentUsername()` — prefers the `email` claim of a `JwtAuthenticationToken`, then `HellodataAuthenticationToken.getEmail()`,
  both **upper-cased**; falls back to `principal.toString()`, and to the literal `"SYSTEM"` when there is no authentication.
  This is what `TrackedEntityListener` stamps into `createdBy`/`modifiedBy`, so audit columns hold upper-cased e-mails and
  background/startup work is attributed to `SYSTEM`.
- `getCurrentUserId()` — `UUID` or `null`.
- `getCurrentUserEmail()` — the raw (non-upper-cased) e-mail or `null`.
- `getCurrentUserFullName()` — `firstname + " " + lastName`.
- `getCurrentUserPermissions()` — the permission set, or an **empty set** when the authentication is not a
  `HellodataAuthenticationToken`.
- `isSuperuser()` — `false` unless the authentication is a `HellodataAuthenticationToken` with the flag set.

Every accessor except `getCurrentUsername()` degrades to `null`/empty/`false` rather than throwing, so a service that forgets
to null-check will fail closed on identity but must still be explicit about authorization.

One deliberate exception is worth knowing: `UserController.getPermissionsForCurrentUser()` (`GET /users/current/profile`)
takes `userId` and `email` from `SecurityUtils` but re-reads the superuser flag with `userService.isUserSuperuser(...)` —
the in-code comment says "Fetch isSuperuser from database to avoid using cached token value". Treat the token's `superuser`
flag as accurate up to the cache/token lifetime, not as a real-time value.

### 6. Method security enforces the permission

`@EnableMethodSecurity` on `SecurityConfig` activates `@PreAuthorize`, which controllers apply as
`@PreAuthorize("hasAnyAuthority('<PERMISSION_NAME>')")` — the string is a `Permission` enum constant name. There are 62
occurrences across 13 controllers today, applied either at class level (e.g. `PortalRoleController` →
`ROLE_MANAGEMENT`, `DashboardGroupController` → `DASHBOARD_GROUPS_MANAGEMENT`) or per method (`UserController` uses
`USER_MANAGEMENT` on 14 endpoints, `DASHBOARDS` on `GET /users/contexts`).

## Request sequence

```mermaid
sequenceDiagram
  autonumber
  actor User as Portal user
  participant UI as hello-data-portal-ui<br/>Angular SPA
  participant KC as Keycloak<br/>realm hello-data.auth-server.realm
  participant FC as SecurityConfig.filterChain<br/>oauth2ResourceServer + jwt
  participant CV as HellodataAuthenticationConverter<br/>convert(Jwt)
  participant DB as UserRepository / portal DB
  participant AP as AutoProvisionService
  participant CTX as SecurityContextHolder<br/>HellodataAuthenticationToken
  participant MS as @EnableMethodSecurity<br/>@PreAuthorize
  participant CTL as Controller method
  participant SVC as Service<br/>SecurityUtils.*

  User->>UI: open portal
  UI->>KC: OIDC authorization-code login
  KC-->>UI: access token (JWT: sub, email, given_name, family_name)
  UI->>FC: GET /api/... with Authorization: Bearer <JWT>

  alt path in AUTH_WHITELIST (swagger, /actuator/**, /)
    FC->>CTL: permitAll — no authentication required
  else any other path
    FC->>FC: validate signature / issuer against jwt.issuer-uri
    FC->>CV: jwtAuthenticationConverter.convert(jwt)
    CV->>DB: findUserEntityByEmailIgnoreCase(email) via Caffeine userDatabaseCache
    alt no portal user yet
      CV->>AP: autoProvisionIfEnabled(email, givenName, familyName, sub)
      AP-->>CV: UserEntity or null (feature flag off)
      CV->>CV: invalidateUserCache(email); re-read
    end
    alt superuser
      CV->>CV: permissions = all Permission.values()
    else regular user
      CV->>DB: getPermissionsFromAllRoles() via userPermissionsCache
    end
    CV-->>FC: HellodataAuthenticationToken(userId, firstname, lastName, email, superuser, permissions)
    FC->>CTX: store token; authorities = SimpleGrantedAuthority per permission
    CTX->>MS: anyRequest().authenticated() satisfied
    MS->>MS: evaluate hasAnyAuthority('USER_MANAGEMENT')
    alt authority present
      MS->>CTL: invoke handler
      CTL->>SVC: business call
      SVC->>CTX: SecurityUtils.getCurrentUserId() / getCurrentUserEmail() / isSuperuser()
      CTL-->>UI: 200 + payload
    else authority missing
      MS-->>UI: 403 Forbidden
    end
  end

  Note over CV,DB: role change → UserService calls invalidateUserCache(email)<br/>so the next request rebuilds permissions
```

## Default deny

**Every non-public endpoint carries an explicit authorization check, and privileged operations must never be reachable on an
unauthenticated path.** Concretely, this rests on three layers that must all hold:

1. **Transport layer** — `auth.anyRequest().authenticated()` in `filterChain`. Only `AUTH_WHITELIST` escapes it, and that list
   is documentation and actuator surface, not business functionality. Adding an entry to `AUTH_WHITELIST` is a security
   decision: it removes *all* authentication from that path, so it must never cover a controller that mutates state or
   returns tenant data.
2. **Method layer** — `@PreAuthorize` naming a `Permission` constant on every controller method that reads or writes
   domain data. Authentication alone is not authorization: a user with an empty permission set is a valid authenticated
   caller, so an endpoint without a check is effectively open to every logged-in user of the tenant.
3. **Data layer** — context scoping. A permission says *what* an operation is; the `contextKey` on the user's role rows says
   *where* it applies. See [02 — Tenancy Model](./02-tenancy-model.md) and
   [Roles / Authorization Concept](../docs/manuals/role-authorization-concept.md).

Rules that follow, for anyone adding an endpoint:

- New controller method → add `@PreAuthorize` (or inherit a class-level one) in the same commit as the mapping.
- Never rely on the UI's `PermissionsGuard` / `requiredPermissions` route data for enforcement. Those exist to hide controls;
  the API is the only enforcement point.
- Never rely on `SecurityUtils.isSuperuser()` *instead of* a `@PreAuthorize` — superusers already receive every `Permission`,
  so the annotation covers them; an `isSuperuser()` branch inside a service is an extra narrowing, not a substitute.
- A permission constant used in an annotation must exist in the `Permission` enum. `@PreAuthorize` strings are not
  compile-checked — a typo silently produces an authority nobody holds (fail-closed), or, if it names an unrelated
  permission, grants the wrong audience (fail-open). Cross-check against the enum.

### Observed gaps in the current code

Stated plainly so the principle is not read as a description of a finished state. Three controllers carry **no**
`@PreAuthorize` today and are therefore reachable by any authenticated user of the tenant, including one auto-provisioned
with the viewer default:

| Endpoint | Controller | Nature |
| --- | --- | --- |
| `GET /roles` | `ch.bedag.dap.hellodata.portal.role.controller.RoleController` | read-only role catalogue |
| `GET /pipelines` | `ch.bedag.dap.hellodata.portal.orchestration.controller.PipelineController` | read-only pipeline list |
| `GET /monitoring/storage-size/latest` | `ch.bedag.dap.hellodata.portal.monitoring.controller.MonitoringController` | read-only storage figures |

All three are `GET` and non-mutating, and all three are behind `authenticated()`. They are nonetheless the places where the
"explicit check on every non-public endpoint" rule is not yet met — closing them (`ROLE_MANAGEMENT`, a pipeline/orchestration
permission, `MONITORING`) is the natural follow-up. A handful of `UserController` endpoints are also intentionally
unannotated because they are strictly self-scoped (`GET /users/current/profile`, `GET /users/current/context-roles`,
`GET /users/data-domains`) — those resolve their subject from `SecurityUtils.getCurrentUserId()` and cannot address another
user, so authentication is the correct boundary. `GET /users/admin-emails` is unannotated and returns the e-mail addresses of
HelloDATA admins to any authenticated caller; whether that is intended is worth confirming with the role/authorization epic.

## Converter caching and invalidation

The converter runs on **every authenticated request**, so it caches to avoid two DB round-trips per call. Both caches are
Caffeine, keyed by e-mail, `maximumSize(1000)`, `expireAfterWrite(...)`:

| Cache | Holds | TTL property |
| --- | --- | --- |
| `userDatabaseCache` | `UserDto` for the caller | `hello-data.cache.user-database-ttl-minutes` (code default 2) |
| `userPermissionsCache` | `List<String>` of portal permissions | `hello-data.cache.user-permission-ttl-minutes` (code default 2) |

Both are **local to the JVM**. They are distinct from the Redis-backed caches configured in
`ch.bedag.dap.hellodata.portal.base.config.RedisConfig` (`users_with_dashboards`, `subsystem_users`, TTLs
`hello-data.cache.users-with-dashboards-ttl-minutes` / `-subsystem-users-ttl-minutes`). In a multi-replica deployment each
replica holds its own converter caches, so an invalidation on one replica does not reach the others — permission changes
converge within the TTL, not instantly, across replicas.

Invalidation API, both public on the converter:

- `invalidateUserCache(String email)` — drops that user's entries from **both** caches. Called by the converter itself after
  an auto-provision (and after a concurrent-provision retry), and by
  `ch.bedag.dap.hellodata.portal.user.service.UserService` immediately after context roles, dashboards and comment
  permissions are updated, "so permissions are refreshed immediately".
- `invalidateAllUserCaches()` — drops both caches entirely. The blunt instrument for changes that can affect many users at
  once (for example a role definition changing rather than a single assignment). It is defined and available; no caller
  exists in the repository today, so wire it in deliberately rather than assuming it already runs.

**Rule:** any code path that changes a user's portal roles, their role's permissions, or their superuser status must call
`invalidateUserCache(...)` for the affected e-mail (or `invalidateAllUserCaches()` when the blast radius is broad).
Otherwise the change is invisible until the TTL elapses.

**Caveat on TTL configuration.** As written, the TTL fields are `@Value`-annotated *instance fields* while the Caffeine caches
are built in *field initializers* on the same class. Field initializers run during construction, before Spring performs field
injection, so the builders observe the fields' default value (`0`) rather than the configured or defaulted property value —
`expireAfterWrite(0, MINUTES)` makes entries eligible for expiry immediately, which means the caches provide far less (or no)
reuse than the property names suggest. Neither property is set in `application.yml`. Flagged here as an observation about the
code as it stands; correcting it (constructor injection, `@PostConstruct` construction, or a `@ConfigurationProperties`
record) is a code change and out of scope for this document.

## Related concerns, deliberately elsewhere

### The role catalogue

Roles are not defined by this chapter. The catalogue lives in `hello-data-commons`:
`ch.bedag.dap.hellodata.commons.sidecars.context.role.HdRoleName` (the context-scoped role constants and
`getByContextType(...)`), `ch.bedag.dap.hellodata.portalcommon.role.entity.RoleEntity` and `PortalRoleEntity` (persisted role
rows and their `Permissions`), and the assignment rows `UserContextRoleEntity` / `UserPortalRoleEntity`. What each role means,
which permissions it should carry, and how business- and data-domain scoping interact are owned by the role/authorization
epic and documented in [Roles / Authorization Concept](../docs/manuals/role-authorization-concept.md). The only contract this
chapter depends on is `UserEntity.getPermissionsFromAllRoles()` returning permission **names** that match `Permission`
constants.

### The seeded local admin

`ch.bedag.dap.hellodata.portal.initialize.service.DefaultUserInitializer` (a component invoked from the `Initializer`
`CommandLineRunner`) reads `ch.bedag.dap.hellodata.portal.user.conf.DefaultAdminProperties`
(`@ConfigurationProperties("hello-data.default-admin")`, exposing `firstName`, `lastName`, `username`, `email`, `password`).
`initDefaultUsers()` returns early with a warning when no `hello-data.default-admin.email` is configured; otherwise it
reconciles against Keycloak — creating the user through the Keycloak Admin client when absent, otherwise only marking the
existing one — writes a `DefaultUserEntity` marker row so later runs are idempotent, promotes the user via
`RoleService.setBusinessDomainRoleForUser(..., HdRoleName.HELLODATA_ADMIN)` and
`setAllDataDomainRolesForUser(..., HdRoleName.DATA_DOMAIN_ADMIN)`, and refuses to proceed (`IllegalStateException`) when the
configured username and e-mail resolve to two different Keycloak users.

This is an **initialization concern, not an authentication path**: the seeded admin still logs in through Keycloak and is
still converted by `HellodataAuthenticationConverter` like anyone else — there is no bypass of the filter chain, and
`hello-data.default-admin.password` is only ever handed to the Keycloak Admin API at creation time. Because it nonetheless
creates a fully privileged account from static configuration, the decision (its local/bootstrap-only intent, the requirement
to leave `hello-data.default-admin.*` unset or the account disabled in shared environments, and the alternatives considered)
is recorded as an ADR in [09 — Architecture Decisions](./09-architecture-decisions.md) — **(planned)**; that chapter does not
exist yet, and this section is the placeholder until it does. The same applies to the `create-example-users` profile and
`hello-data.example-users.*` used by `ExampleUsersInitializer`.

Never place secrets for these properties in the repository; supply them per environment through the deployment's
configuration mechanism and reference them by property name in documentation, as done here.

## Related spec chapters

The `docs/spec/` tree does not exist in the repository yet — **every** link below is to a **(planned)** chapter and will
resolve only once that chapter is added:

- [Authentication and authorization spec](../spec/01-authentication-and-authorization.md) — **(planned)**; the normative contract for `SecurityConfig`, `HellodataAuthenticationConverter`, token claims consumed, and the per-endpoint `@PreAuthorize` matrix.
- [Event contracts spec](../spec/02-event-contracts.md) — **(planned)**; `UserContextRoleUpdate` / `AllUsersContextRoleUpdate` payloads that propagate role changes to subsystems after a cache invalidation.
- [Portal persistence spec](../spec/03-portal-persistence.md) — **(planned)**; the `user_`, `default_user`, `role`, `portal_role`, `user_context_role` and `user_portal_role` tables behind `getPermissionsFromAllRoles()`.
- [Sidecar integration spec](../spec/04-sidecar-integration.md) — **(planned)**; how subsystem-side users and roles are reconciled with the portal identity.
- [Configuration and deployment spec](../spec/05-configuration-and-deployment.md) — **(planned)**; `hello-data.auth-server.*`, `spring.security.oauth2.*`, `hello-data.cors.allowed-origins`, `hello-data.cache.*`, `hello-data.default-admin.*` and the `disable-csrf` / `disable-cors` / `disable-frame-options` / `create-example-users` profiles.