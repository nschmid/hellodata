# 06 — Messaging Taxonomy

Chapter (f) of the architecture frame. Chapter (a) is [01 — Context and Overview](./01-context-and-overview.md), chapter (b)
is [02 — Tenancy Model](./02-tenancy-model.md), chapter (c) is [03 — Module Breakdown](./03-module-breakdown.md), chapter (d)
is [04 — Identity and Authorization](./04-identity-and-authorization.md), chapter (e) is
[05 — State Ownership](./05-state-ownership.md).

The portal and the sidecars share **no Maven dependency edge and no HTTP endpoint**. Everything they exchange crosses NATS.
This chapter is the map of that surface: the vocabulary that names a message, the Spring machinery that publishes and
consumes one, the payload contracts on the wire, and the two delivery rules — **at-least-once** and **publish-after-commit** —
that every producer and consumer must be written against. Everything named below exists in the repository; anything that does
not is marked **(planned)** or **(planned/uncertain)**.

## Scope: what this chapter owns, and what it does not

| Concern | Owner | Where |
| --- | --- | --- |
| The message vocabulary and its subjects | **this chapter** | `HDEvent`, `HDStream`, `RequestReplySubject` |
| Publish / subscribe plumbing and its failure behaviour | **this chapter** | `hello-data-commons/hello-data-nats-spring` |
| Delivery semantics and the idempotency obligation | **this chapter** | `SubscribeAnnotationThread.passMessageToSpringBean` |
| Publish-after-commit ordering | **this chapter** | `DashboardGroupService`, `UserSyncEventListener` |
| Which store may hold what, and why NATS is not one | [05 — State Ownership](./05-state-ownership.md) | `NatsStreamUtil.createStream` retention |
| Field-by-field payload schemas | event contracts spec | `resources/v1/**` in `hello-data-sidecar-common` |
| Where a new event class belongs in the module stack | [03 — Module Breakdown](./03-module-breakdown.md) | ring 1b / ring 2b |
| Why NATS at all, versus a queue or direct HTTP | [09 — Architecture Decisions](./09-architecture-decisions.md) — **(planned)** | ADR records |

**Legend used in the tables below.** `portal-api` = `hello-data-portal-api`; `portal-sc` = `hello-data-sidecar-portal`;
`superset-sc`, `airflow-sc`, `dbt-sc`, `cb-sc` (cloudbeaver), `jh-sc` (jupyterhub), `sftpgo-sc` = the matching
`hello-data-sidecars/*` module; `monitoring` = `hello-data-subsystems/hello-data-monitoring-storage`. "METAINFO" is
`HDStream.METAINFO_STREAM`.

## 1. The vocabulary

Three enums in `ch.bedag.dap.hellodata.commons.sidecars.events` (module `hello-data-sidecar-common`, ring 1b) are the entire
naming surface. Nothing outside them may name a subject.

### `HDEvent` — the JetStream catalogue

Each constant binds three things together: a stream, a subject string, and the payload class.

```java
PUBLISH_APP_INFO_RESOURCES(METAINFO_STREAM, "publish_resources.app_info", AppInfoResource.class),
...
COMMENCE_USERS_SYNC(METAINFO_STREAM, "commence_users_sync"),   // second ctor → dataClass = Void.class
```

Accessors: `getStream()`, `getSubject()`, `getDataClass()`, and `getStreamName()` — the last returning `stream.name()`, the
plain string the NATS client needs. `getStreamName()` is what both the publisher (`NatsSenderService`) and the subscriber
(`NatsConfigBeanPostProcessor`, `SubscribeAnnotationThread`) call, so the *enum constant name* is the wire stream name. A
rename of an `HDStream` constant is a wire change, not a refactor.

The two-argument constructor sets `dataClass = Void.class`. That is not a "payloadless event" feature so much as a hole:
`NatsSenderService` checks `event.getDataClass().isInstance(body)`, and nothing is an instance of `Void`, so
`COMMENCE_USERS_SYNC` cannot be published through the sender at all.

### `HDStream` — the stream names

```java
public enum HDStream { METAINFO_STREAM }
```

One constant. Every event today lives in one stream, differentiated only by subject. "Pick the stream" is therefore a
one-option decision until a second constant is added — and adding one means the new stream must be created on both the
publishing and the subscribing side (`NatsStreamUtil.createOrUpdateStream` is called from both).

### `RequestReplySubject` — the synchronous side

Subjects for the NATS **core** request/reply pattern, which does *not* go through JetStream at all:

| Constant | Subject fragment | Used today |
| --- | --- | --- |
| `UPLOAD_DASHBOARDS_FILE` | `-upload_dashboards_file` | yes |
| `GET_QUERY_LIST` | `-get_query_list` | yes |
| `GET_DASHBOARD_ACCESS_LIST` | `-get_logs_list` | yes |
| `VALIDATE_DASHBOARD_POINTERS` | `-validate_dashboard_pointers` | yes |
| `NATS_CONNECTION_HEALTH_CHECK` | `nats_connection_health_check` | yes |
| `UPDATE_DASHBOARD_ROLES_FOR_USER` | `-update_dashboard_roles_for_user` | **no caller in the repository** |

The leading `-` is deliberate: these fragments are concatenated *after* an instance name and then slugified —
`SlugifyUtil.slugify(supersetInstanceName + RequestReplySubject.GET_QUERY_LIST.getSubject())`. That is how one subject
addresses one Superset instance in one data domain. `NATS_CONNECTION_HEALTH_CHECK` has no leading dash because
`NatsHealthIndicator` composes it differently: `appName + "-" + slugify(subject) + ("-" + instanceName if set)`, then
Base64-encodes the result as the actual subject.

## 2. The Spring integration — `hello-data-nats-spring`

This module (ring 2b) is the **only** code that touches the `io.nats` client API. Everything else speaks in `HDEvent`s.

| Type | Role |
| --- | --- |
| `@EnableJetStream` | Type-level annotation that `@Import`s `NatsConfiguration`. The opt-in switch; `portal-api` puts it on `base.config.JetStreamConfig`, each sidecar on its `@SpringBootApplication` class |
| `NatsConfiguration` | `extends NatsAutoConfiguration implements AsyncConfigurer, ConnectionListener`; `@EnableAsync`; logs every connection event; declares `NatsConfigBeanPostProcessor`, a fallback `ObjectMapper` (JSR-310), and `NatsHealthIndicator` |
| `@JetStreamSubscribe` | Method-level, meta-annotated `@Transactional`; carries `event()`, `timeoutMinutes()` (default 5), `asyncRun()` (default true) |
| `NatsConfigBeanPostProcessor` | Scans every bean for the annotation, validates the handler signature, and creates or joins a subscription thread |
| `SubscribeAnnotationThread` | One thread per `stream + subject`; owns the durable consumer, the fetch loop, the dispatch and the ack |
| `BeanMethodWrapper` | `(method, bean, subscriptionId)` record — the reflective invocation target |
| `NatsSenderService` | `publishMessageToJetStream(HDEvent, T body)` — the single sanctioned publish path |
| `NatsStreamUtil` | `createOrUpdateStream(jsm, streamName, subject)`; creates the stream on first use, or adds the subject to an existing one |
| `NatsHealthIndicator` | Actuator health contributor that proves the request/reply path works, not merely that the socket is open |
| `NatsException` | The single error type raised by publish-side failures |

### Publishing

`NatsSenderService.publishMessageToJetStream(HDEvent, T)` does, in order:

1. **Type check** — `if (!event.getDataClass().isInstance(body)) throw new NatsException(...)`. The event/payload pairing in
   `HDEvent` is enforced at runtime on every publish.
2. **Connection check** — throws if `connection.getStatus() != CONNECTED`, with the message "Message will be retried on the
   next scheduled run". Publishing is *not* buffered: a disconnected NATS means the caller's publish fails.
3. **Stream ensure** — `NatsStreamUtil.createOrUpdateStream(...)` on every publish, so a fresh NATS deployment self-provisions.
4. **Serialise** — `objectMapper.writeValueAsString(body)`, unless the body is already a `String`.
5. **Publish** — with `PublishOptions.expectedStream(streamName)` and a random `messageId` (`UUID.randomUUID()`), returning
   the `PublishAck`.

Note step 5 against the stream config from [05 — State Ownership](./05-state-ownership.md): the stream is created with
`duplicateWindow = Duration.ZERO`, so the message id buys **no** server-side deduplication. It is a correlation id, not an
idempotency key — which is precisely why the obligation lands on the subscriber.

### Subscribing

`NatsConfigBeanPostProcessor.postProcessAfterInitialization` reflects over every bean's public methods. For each
`@JetStreamSubscribe` it enforces the handler shape:

> the method must take **exactly one** parameter, of exactly `event().getDataClass()` — otherwise a `NatsException` is thrown
> at context startup, naming the method and the expected type.

It then computes `subscriptionId = stream + "_" + subject`. If a thread for that id already exists, the new
`BeanMethodWrapper` is appended to it — **several beans may subscribe to the same event, and one message is delivered to all
of them in turn**. Otherwise a new `SubscribeAnnotationThread` is created with a durable name of

```text
slugify(spring.application.name + "-" + stream + "-" + subject + ["-" + hello-data.instance.name])
```

so the durable consumer is per application *and* per instance where `hello-data.instance.name` is set. The pool is a fixed
thread pool sized `roundUpToNextMultipleOfTen(HDEvent.values().length * 3)`; `destroy()` stops every thread and awaits
termination for 20 s.

`SubscribeAnnotationThread` runs a loop: ensure the subscription, `checkOrCreateConsumer()` (re-subscribing if the durable
consumer vanished server-side), then `nextMessage(Duration.ofSeconds(10))`. The consumer is built with
`ackWait(Duration.ofMinutes(subscribeAnnotation.timeoutMinutes()))` — the annotation's timeout **is** the redelivery window.
With `asyncRun = true` (the default) the message is handed to the shared executor with a cancellation timer; with
`asyncRun = false` it is processed on the fetch thread, serialising that subject.

Failure handling is aggressive and worth knowing before adding a subscriber: `hello-data.on-error.kill-jvm` (default `true`)
with `hello-data.on-error.kill-jvm-counter` (default `20`) makes the thread call `System.exit(1)` after repeated
connection/subscription failures, and `run()` ends with `System.exit(1)` unconditionally once the loop exits. The design
intent is "let the orchestrator restart me" rather than "run degraded".

### Health

`NatsHealthIndicator` subscribes a `Dispatcher` to its own Base64-encoded subject at `@PostConstruct` and, on every health
check, sends itself a `request(...)` with a 1 s timeout. `CONNECTED` plus a non-null reply → `up()`; `CONNECTING`/
`RECONNECTING` → `outOfService()`; anything else → `down()`. It then reads `METAINFO_STREAM`'s `StreamInfo` and marks down if
that throws. So the indicator asserts the *round trip*, not just the socket.

## 3. Payload contracts

All payload types live in `hello-data-sidecar-common`. Nothing else may define a wire type — that is the rule that keeps
portal and sidecars deployable independently.

### `HdResource` — subsystem state flowing *towards* the portal

```java
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "kind")
@JsonSubTypes({ AppInfoResource, DashboardResource, UserResource, PermissionResource, RoleResource, PipelineResource })
public interface HdResource extends Serializable
```

Members: `getApiVersion()`, `getModuleType()`, `getKind()`, `getInstanceName()`, `getData()`, and a default `getSummary()`
formatting `[module-type][kind][instance-name][api-version]`. Each implementation pins `apiVersion = "v1"` and its `kind` to
a `ModuleResourceKind` constant, marks those plus `moduleType`/`instanceName` as the `@EqualsAndHashCode` identity, and
carries the real content in `data`.

`UserResource.toString()` returns `getSummary()` — deliberately the metadata line, not the user list. Copy that pattern in
new resource types; see the logging rule below.

### The `*Update` / `*Delete` data classes — portal intent flowing *towards* subsystems

| Type | Carries | Notes |
| --- | --- | --- |
| `SubsystemUserUpdate` | `firstName`, `lastName`, `email`, **`password`**, `username`, `active`, `roles`, `sendBackUsersList` | payload of `CREATE_USER` / `ENABLE_USER` / `DISABLE_USER` |
| `SubsystemUserDelete` | `email`, `username` | payload of `DELETE_USER` |
| `UserContextRoleUpdate` | identity fields plus `contextRoles` (`contextKey`, `parentContextKey`, `HdRoleName`), `extraModuleRoles`, `dashboardsPerContext`, `sendBackUsersList` | the main role-propagation payload |
| `AllUsersContextRoleUpdate` | a batch of `UserContextRoleUpdate` | payload of `SYNC_USERS`, sent in partitions |
| `UserCacheUpdate` | `moduleType` only | the cache-refresh hint of [05 — State Ownership](./05-state-ownership.md) |
| `SubsystemGetAllUsers` | — | payload of `GET_ALL_USERS` |
| `SubsystemUser` / `SubsystemRole` | the subsystem-side user and role shape inside `UserResource` | snake_case via `@JsonProperty` |
| `DashboardCommentsPublished` | `contextKey`, `dashboardId`, `List<PublishedComment>` | its javadoc states "the consumer does a full-replace for idempotent sync" |
| `StorageMonitoringResult` | storage/database sizes | published by `monitoring` |

Every one of these is annotated `@JsonIgnoreProperties(ignoreUnknown = true)`. That is the forward-compatibility contract:
**adding a field is safe; renaming or removing one breaks every sidecar until it is redeployed.**

## 4. Delivery semantics

### At-least-once — so every subscriber must be idempotent

The ack is at the end of `SubscribeAnnotationThread.passMessageToSpringBean`:

```java
for (BeanMethodWrapper beanWrapper : beanWrappers) {
    beanWrapper.method().invoke(beanWrapper.bean(), getObjectMapper().readValue(message.getData(), clazz));
}
message.ack();
} catch (IllegalAccessException | InvocationTargetException | IOException | RuntimeException e) {
    log.error("[NATS] Error invoking method", e);
}
```

Three consequences follow directly, and they are the reason idempotency is not optional:

1. **A handler that throws never reaches `message.ack()`.** The exception is caught and logged, the message stays unacked,
   and JetStream redelivers it after `ackWait` — i.e. after `timeoutMinutes` (default 5, 15 on the `SYNC_USERS` consumers).
2. **A partial success is redelivered in full.** If three beans subscribe to one event and the second throws, the first has
   already run and will run again on redelivery.
3. **A crash between the side effect and the ack is invisible.** The work happened; the broker does not know.

There is no dedup net anywhere else: `duplicateWindow` is `Duration.ZERO`, the message id is random per publish, and
`maxAge` is 10 minutes. **A handler must therefore produce the same end state when run twice with the same message.**
The practices already in the code are the ones to copy:

- **Full replace over delta** — `DashboardCommentsPublished` carries every published comment for a `(contextKey, dashboardId)`
  pair so the consumer replaces rather than appends.
- **Upsert over insert** — `CbCreateUserConsumer` looks the user up first and logs "already exists in instance, omitting
  creation" instead of failing.
- **Recompute over increment** — `CacheUpdateService` responds to `UPDATE_METAINFO_USERS_CACHE` by recomputing both caches
  from Postgres, under an advisory lock. Running it twice costs time and nothing else.

Anything that increments a counter, appends to a list, or sends a one-shot notification needs an explicit guard.

### Publish-after-commit

**An event must not be published until the transaction that produced the state it describes has committed.** Otherwise a
subscriber — often on another host, sometimes within milliseconds — reads the database and sees the old value, or acts on a
change that then rolls back. Because JetStream will happily redeliver, a premature publish does not self-heal; it produces a
subsystem that is confidently wrong.

The concrete pattern in this repository is `ch.bedag.dap.hellodata.portal.dashboard_group.service.DashboardGroupService`.
All three mutating methods (`create`, `update`, `delete`) are `@Transactional`, compute the affected user set *inside* the
transaction, and then defer:

```java
TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
    @Override
    public void afterCommit() {
        for (String userId : usersToSyncCopy) {
            eventPublisher.publishEvent(new UserDashboardSyncEvent(UUID.fromString(userId), contextKey));
        }
    }
});
```

The in-code comment states the intent exactly: *"Sync affected users to Superset after transaction commits, so async event
handlers see committed data."* Note also `Set.copyOf(usersToSync)` — the deferred callback captures an immutable snapshot
rather than a collection that could still be mutated.

The second hop is `ch.bedag.dap.hellodata.portal.user.event.UserSyncEventListener`, whose handlers are
`@Async @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)` and which calls
`UserSubsystemSyncService.synchronizeUserWithDashboards(...)` → `publishMessageToJetStream(UPDATE_USER_CONTEXT_ROLE, ...)`.
Each handler wraps its body in try/catch so one user's failure does not abort the rest.

So there are two mechanisms in use, and both are acceptable:

- **`@TransactionalEventListener(AFTER_COMMIT)`** — the default choice. Publish a Spring `ApplicationEvent` from inside the
  transactional service and let Spring hold it until commit.
- **`TransactionSynchronizationManager.registerSynchronization(...)`** — for when you need the callback registered against a
  specific transaction at a specific point, as `DashboardGroupService` does.

What is **not** acceptable is calling `natsSenderService.publishMessageToJetStream(...)` directly from inside a
`@Transactional` method that has not yet committed.

## 5. Event map — evidenced pairs only

Every row below is backed by a `publishMessageToJetStream` call site and/or a `@JetStreamSubscribe` method in this
repository. Rows with no evidenced counterpart say so rather than guessing.

| Event · subject | Stream | Publisher(s) | Subscriber(s) | Payload |
| --- | --- | --- | --- | --- |
| `PUBLISH_APP_INFO_RESOURCES` · `publish_resources.app_info` | METAINFO | superset-sc, airflow-sc, dbt-sc, cb-sc, jh-sc, sftpgo-sc | portal-sc, cb-sc, sftpgo-sc | `AppInfoResource` |
| `PUBLISH_DASHBOARD_RESOURCES` · `publish_resources.dashboard` | METAINFO | superset-sc | portal-sc | `DashboardResource` |
| `PUBLISH_ROLE_RESOURCES` · `publish_resources.role` | METAINFO | superset-sc, airflow-sc, dbt-sc, cb-sc | portal-sc | `RoleResource` |
| `PUBLISH_PERMISSION_RESOURCES` · `publish_resources.permission` | METAINFO | superset-sc, airflow-sc, dbt-sc, cb-sc | portal-sc | `PermissionResource` |
| `PUBLISH_PIPELINE_RESOURCES` · `publish_resources.pipeline` | METAINFO | airflow-sc | portal-sc | `PipelineResource` |
| `PUBLISH_USER_RESOURCES` · `publish_resources.user` | METAINFO | superset-sc, airflow-sc, dbt-sc, cb-sc, sftpgo-sc | portal-sc | `UserResource` |
| `UPDATE_METAINFO_USERS_CACHE` · `user_cache_update` | METAINFO | portal-sc `PublishedUserResourcesConsumer` | portal-api `CacheUpdateService` | `UserCacheUpdate` |
| `CREATE_USER` · `create_user` | METAINFO | portal-api `UserService`, `AutoProvisionService` | superset-sc, airflow-sc, dbt-sc, cb-sc, sftpgo-sc | `SubsystemUserUpdate` |
| `ENABLE_USER` · `enable_user` | METAINFO | portal-api `UserService` | superset-sc, sftpgo-sc | `SubsystemUserUpdate` |
| `DISABLE_USER` · `disable_user` | METAINFO | portal-api `UserService` | superset-sc, airflow-sc, sftpgo-sc | `SubsystemUserUpdate` |
| `DELETE_USER` · `delete_user` | METAINFO | portal-api `UserService` | superset-sc, airflow-sc, dbt-sc, cb-sc, sftpgo-sc | `SubsystemUserDelete` |
| `UPDATE_USER_CONTEXT_ROLE` · `update_user_context_role` | METAINFO | portal-api `UserSubsystemSyncService` | portal-sc, superset-sc, airflow-sc, dbt-sc, cb-sc, sftpgo-sc | `UserContextRoleUpdate` |
| `SYNC_USERS` · `sync_users` | METAINFO | portal-api `UserSubsystemSyncService` | portal-sc, superset-sc, airflow-sc, dbt-sc, cb-sc, sftpgo-sc | `AllUsersContextRoleUpdate` |
| `UPDATE_STORAGE_MONITORING_RESULT` · `update_storage_monitoring_result` | METAINFO | monitoring `StorageMonitoringService` | portal-sc `PublishedStorageSizeConsumer` | `StorageMonitoringResult` |
| `PUBLISH_DASHBOARD_COMMENTS` · `publish_resources.dashboard_comments` | METAINFO | portal-api `DashboardCommentDwhSyncService` | superset-sc `PublishedCommentResourcesConsumer` | `DashboardCommentsPublished` |
| `GET_ALL_USERS` · `users_refresh` | METAINFO | **no publisher in the repository** | superset-sc, airflow-sc, dbt-sc, cb-sc, sftpgo-sc | `SubsystemGetAllUsers` |
| `COMMENCE_USERS_SYNC` · `commence_users_sync` | METAINFO | **none** | **none** | `Void.class` — unpublishable (see §1) |

Two rows deserve emphasis rather than a footnote. **`GET_ALL_USERS` has five subscribers and no publisher**: every sidecar is
ready to dump its user list on request, but nothing asks. Whether the trigger is missing or was replaced by the
`sendBackUsersList` flag on `UserContextRoleUpdate` / `SubsystemUserUpdate` is **(planned/uncertain)** — that flag is the
mechanism actually in use for pushback today. **`COMMENCE_USERS_SYNC` is referenced nowhere** outside its own declaration.

### Request/reply pairs

These use core NATS `connection.request(...)` against a `Dispatcher`, **not** JetStream: no stream, no durable consumer, no
redelivery. The failure mode is a `null` reply after the timeout, and each caller handles it explicitly.

| Subject (composed) | Requester | Responder | Request → reply |
| --- | --- | --- | --- |
| `slugify(<instance> + "-upload_dashboards_file")` | portal-api `DashboardService.uploadDashboardsFile` | superset-sc `UploadDashboardsFileListener` | `DashboardUpload` chunks (0.5 MB) → `"OK"` or an error string |
| `slugify(<instance> + "-validate_dashboard_pointers")` | portal-api `DashboardCommentService.requestPointerValidity` | superset-sc `DashboardPointerValidationRequestListener` | `DashboardPointerValidationRequest` → `DashboardPointerValidationResponse` |
| `slugify(<instance> + "-get_query_list")` | portal-sc `QuerySynchronizer` | superset-sc `QueryListRequestListener` | JSON `{filters, page, pageSize}` (or a legacy bare array) → `{result, count}` |
| `slugify(<instance> + "-get_logs_list")` | portal-sc `DashboardAccessSynchronizer` | superset-sc `DashboardAccessListRequestListener` | JSON request → JSON access list |
| `base64(<app>-nats-connection-health-check[-<instance>])` | any app's `NatsHealthIndicator` | the same app's `NatsHealthIndicator` | subject string → `"OK"` |
| `<instance>-update_dashboard_roles_for_user` | — | — | constant declared, **no caller** — **(planned/uncertain)** |

Timeouts are per call site and deliberately uneven: 60 s for a dashboard chunk, 5 minutes when the last chunk also prunes,
30 s for pointer validation, 1 s for the health probe.

## 6. One publish-after-commit round trip

```mermaid
sequenceDiagram
  autonumber
  actor Admin as Portal admin
  participant CTL as DashboardGroupController<br/>@PreAuthorize('DASHBOARD_GROUPS_MANAGEMENT')
  participant SVC as DashboardGroupService.update<br/>@Transactional
  participant DB as PostgreSQL
  participant TSM as TransactionSynchronizationManager
  participant LIS as UserSyncEventListener<br/>@Async @TransactionalEventListener(AFTER_COMMIT)
  participant SYN as UserSubsystemSyncService
  participant SND as NatsSenderService
  participant JS as NATS JetStream<br/>METAINFO_STREAM / update_user_context_role
  participant TH as SubscribeAnnotationThread<br/>durable: hd-sidecar-superset-…
  participant CON as SupersetUpdateUserContextRoleConsumer
  participant SS as Superset REST API

  Admin->>CTL: PUT /dashboard-groups
  CTL->>SVC: update(dto)
  SVC->>DB: findById + save (still uncommitted)
  SVC->>SVC: compute usersToSync; Set.copyOf(...)
  SVC->>TSM: registerSynchronization(afterCommit → publish UserDashboardSyncEvent)
  SVC-->>CTL: return
  CTL->>DB: transaction COMMIT
  Note over TSM,DB: nothing has been published yet — this is the whole point

  DB-->>TSM: commit succeeded
  TSM->>LIS: UserDashboardSyncEvent(userId, contextKey)
  LIS->>SYN: synchronizeUserWithDashboards(userId, contextKey)
  SYN->>DB: read committed roles + dashboards
  SYN->>SND: publishMessageToJetStream(UPDATE_USER_CONTEXT_ROLE, UserContextRoleUpdate)
  SND->>SND: dataClass check; status == CONNECTED?
  SND->>JS: createOrUpdateStream + publish(messageId = random UUID)
  JS-->>SND: PublishAck

  JS->>TH: nextMessage(10s)
  TH->>CON: invoke(UserContextRoleUpdate)
  CON->>SS: apply roles / dashboard permissions

  alt handler returns normally
    TH->>JS: message.ack()
  else handler throws
    TH->>TH: log.error, no ack
    JS-->>TH: redeliver after ackWait (timeoutMinutes)
    Note over CON,SS: same message again → handler MUST be idempotent
  end
```

## 7. One request/reply round trip

```mermaid
sequenceDiagram
  autonumber
  actor Admin as Portal admin
  participant CTL as SupersetController
  participant DS as DashboardService.uploadDashboardsFile
  participant MIS as MetaInfoResourceService
  participant NC as NATS core<br/>subject: slugify(instance + "-upload_dashboards_file")
  participant LSN as UploadDashboardsFileListener<br/>@PostConstruct Dispatcher
  participant SS as Superset REST API

  Admin->>CTL: POST dashboards ZIP (multipart)
  CTL->>DS: uploadDashboardsFile(file, contextKey, prune)
  DS->>MIS: findSupersetInstanceNameByContextKey(contextKey)
  MIS-->>DS: instanceName
  DS->>DS: binaryFileId = UUID; split into 0.5 MB chunks

  loop per chunk
    DS->>NC: connection.request(subject, DashboardUpload, 60s / 5min on last+prune)
    NC->>LSN: dispatch
    alt not the last chunk
      LSN->>LSN: saveChunk(...)
      LSN-->>NC: ack + "OK"
    else last chunk
      LSN->>LSN: assembleChunks + remap DB + optional backup/prune
      LSN->>SS: importDashboard(zip, passwords)
      SS-->>LSN: result
      LSN-->>NC: "OK" or error text
    end
    NC-->>DS: reply
    alt reply == null (timeout)
      DS-->>Admin: 500 — "reply is null, verify superset sidecar or nats connection"
    else reply != "OK"
      DS-->>Admin: 500 with the responder's message
    end
  end

  DS->>DS: refreshPointerStatusForContext(contextKey) — best-effort, own request/reply
  DS-->>Admin: 200
  Note over NC,LSN: core NATS — no stream, no durable consumer, no redelivery.<br/>A timeout is the only failure signal.
```

## 8. Rules for new messages

1. **Name the event in `HDEvent`.** One constant, with its subject string and its payload class. No literal subject string
   anywhere else in the codebase; `NatsSenderService` takes an `HDEvent`, not a string, and that is the enforcement point.
2. **Pick the stream.** Today that means `HDStream.METAINFO_STREAM`. Adding a stream constant is a deployment-visible change:
   the name is the wire name via `getStreamName()`, and both sides call `createOrUpdateStream`.
3. **Keep payloads in `hello-data-sidecar-common`.** Under `resources/v1/...`, `Serializable`, with
   `@JsonIgnoreProperties(ignoreUnknown = true)`. If it is a new resource kind, register it as a `@JsonSubTypes.Type` on
   `HdResource` and add the `kind` constant to `ModuleResourceKind`. Never put a JPA annotation or a portal DTO on the wire.
4. **Treat payload changes as wire changes.** Adding a field is additive. Renaming or removing one breaks every deployed
   sidecar until it is redeployed — see [03 — Module Breakdown](./03-module-breakdown.md).
5. **Make the handler idempotent.** Full-replace, upsert, or recompute; never blind append or increment. Assume the same
   message will arrive twice, and that a previous attempt may have half-completed before it threw.
6. **Match the handler signature exactly** — one parameter, of exactly `event().getDataClass()` — or the application fails at
   startup with a `NatsException`. Set `timeoutMinutes` to something larger than the slowest realistic run (it is also the
   redelivery window), and `asyncRun = false` when the work must be serialised per subject.
7. **Publish after commit, never inside the transaction.** Use `@TransactionalEventListener(AFTER_COMMIT)`, or
   `TransactionSynchronizationManager.registerSynchronization(...)` as `DashboardGroupService` does — and capture an
   immutable snapshot of what the callback needs.
8. **Never carry personal data or secrets into a log statement about the payload.** Do not log the payload object, do not
   `toString()` a `@Data` class on the wire, and do not log a serialised message body. Log the **shape**: instance name,
   `kind`, context key, counts, and at most a single identifying field such as an e-mail where the entry would be useless
   without it. `SubsystemUserUpdate` carries a `password`; `SubsystemUser` and `UserContextRoleUpdate` carry names and
   e-mails; comment payloads carry authored text. `UserResource.toString()` returning `getSummary()` and
   `CbCreateUserConsumer` logging only `getUsername()`/`getEmail()` are the patterns to copy. Passwords, national identifiers
   such as SSNs/AHV numbers, and any other special-category data must never reach a log sink, at any level.
9. **Give the event exactly one owner on each side.** Several beans *may* subscribe to one event (the post-processor appends
   them to the same thread), but they then share an ack: if the second throws, the first re-runs. Prefer one handler that
   fans out in-process.
10. **Do not use the stream as storage.** Interest retention, 10-minute `maxAge`, 2000-message cap. Commit to Postgres
    first; the event only announces. See [05 — State Ownership](./05-state-ownership.md).

## 9. Observations on the current code

Stated plainly, so the rules above are not read as a description of a finished state:

- **A password can reach the logs at `TRACE`.** `NatsSenderService` logs the fully serialised message body
  (`log.trace("... Publishing message {} ...", message)`), and `SubsystemUserUpdate` — a `@Data` class with a `password`
  field — is the payload of `CREATE_USER`. `SubscribeAnnotationThread` and `UploadDashboardsFileListener` similarly log raw
  message data at `DEBUG`. Enabling those levels in a shared environment is a data-protection decision, not a debugging
  convenience. Tightening this (a redacting `toString`, or dropping the body from the trace line) is a code change and out of
  scope for this document.
- **Handler exceptions are swallowed at the dispatch layer.** `passMessageToSpringBean` catches and logs; there is no dead
  letter subject and no failure metric. The only visible symptom of a permanently poisoned message is repeated redelivery
  until `maxAge` expires it.
- **`System.exit(1)` is a normal exit path.** `SubscribeAnnotationThread.run()` ends with it, and `checkFailureCounter()`
  reaches it after `hello-data.on-error.kill-jvm-counter` failures. Intentional (restart-by-orchestrator), but it means a
  NATS outage takes the process with it rather than degrading it.
- **Two after-commit gates in series.** `DashboardGroupService` publishes its `UserDashboardSyncEvent` from inside an
  `afterCommit()` callback, and the listener for that event is *itself* `@TransactionalEventListener(AFTER_COMMIT)` without
  `fallbackExecution`. Worth knowing when tracing why a sync did or did not run: such a listener only fires for an event
  published while a transaction is active.
- **Dead and orphaned constants.** `COMMENCE_USERS_SYNC` (no publisher, no subscriber, and unpublishable because its
  `dataClass` is `Void`), `UPDATE_DASHBOARD_ROLES_FOR_USER` (declared, never used), and `GET_ALL_USERS` (five subscribers,
  no publisher). Each is either a missing trigger or a leftover; resolving which is a code decision.
- **Durable names embed the instance name.** Two replicas of the same application with the same
  `spring.application.name` and no `hello-data.instance.name` compute the *same* durable name. Whether that yields shared
  consumption or a bind conflict depends on the broker; set `hello-data.instance.name` per replica-group deliberately rather
  than relying on the default.

## Related spec chapters

The `docs/spec/` tree does not exist in the repository yet — **every** link below is to a **(planned)** chapter and will
resolve only once that chapter is added:

- [Event contracts spec](../spec/02-event-contracts.md) — **(planned)**; the normative per-event contract: `HDEvent` subject strings, payload schemas under `resources/v1/**`, the additive-change rule, and the idempotency obligation per subscriber.
- [Sidecar integration spec](../spec/04-sidecar-integration.md) — **(planned)**; per-sidecar consumer inventory, the request/reply subject-composition rule (`slugify(instanceName + subject)`), and the responder timeouts each caller expects.
- [Authentication and authorization spec](../spec/01-authentication-and-authorization.md) — **(planned)**; how `UserContextRoleUpdate` / `AllUsersContextRoleUpdate` propagate role changes, and why the API remains the only enforcement point.
- [Portal persistence spec](../spec/03-portal-persistence.md) — **(planned)**; the tables written before an event is published, and the transaction boundaries the publish-after-commit rule depends on.
- [Configuration and deployment spec](../spec/05-configuration-and-deployment.md) — **(planned)**; `nats.spring.server`, `spring.application.name`, `hello-data.instance.name`, `hello-data.on-error.kill-jvm` / `-counter`, and the actuator health surface backed by `NatsHealthIndicator`.