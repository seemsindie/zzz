# Zzz - Project TODO Tracker

## Quick Start

```bash
# Build the project
cd /Users/ivan/projects/zigweb_workspace/zzz
zig build

# Run the server
zig build run
# Server starts at http://127.0.0.1:8888

# Run all tests
zig build test

# Test with curl (in another terminal)
curl http://127.0.0.1:8888/              # HTML welcome page
curl http://127.0.0.1:8888/hello         # Plain text
curl http://127.0.0.1:8888/json          # JSON response
curl http://127.0.0.1:8888/users/42      # Path param extraction
curl http://127.0.0.1:8888/missing       # 404 Not Found
curl -X POST http://127.0.0.1:8888/hello # 405 Method Not Allowed
curl -I http://127.0.0.1:8888/hello      # HEAD (headers only, no body)

# Build optimized release
zig build -Doptimize=ReleaseFast

# Run with arguments
zig build run -- --some-arg
```

---

## Phase 1: Foundation (TCP Server + HTTP/1.1)

- [x] Initialize Zig project with build.zig / build.zig.zon
- [x] Git repository initialized
- [x] Project directory structure created
- [x] HTTP status codes enum with reason phrases (`src/core/http/status.zig`)
- [x] HTTP headers storage with case-insensitive lookup (`src/core/http/headers.zig`)
- [x] HTTP request type with method, path, query, body, version (`src/core/http/request.zig`)
- [x] HTTP method enum (GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, CONNECT, TRACE)
- [x] Zero-copy HTTP/1.1 request parser (`src/core/http/parser.zig`)
- [x] HTTP response builder with .html(), .json(), .text(), .redirect(), .empty() (`src/core/http/response.zig`)
- [x] Response serialization to bytes
- [x] TCP server using Zig 0.16 std.Io networking (`src/core/server.zig`)
- [x] Accept loop with connection handling
- [x] Request body reading (Content-Length based)
- [x] Example app with 4 routes (`src/main.zig`)
- [x] All tests passing (10/10)
- [ ] Chunked transfer encoding (request reading)
- [ ] Chunked transfer encoding (response streaming)
- [ ] Keep-alive connection reuse (currently closes after each response)
- [ ] Configurable request size limits
- [ ] Configurable read/write timeouts
- [ ] Graceful shutdown (signal handling)
- [ ] Multi-threaded accept (worker thread pool)
- [ ] Connection backpressure / max connections limit
- [ ] HTTP/1.0 compatibility mode
- [ ] 100-continue handling

## Phase 1.5: TLS / HTTPS

- [ ] OpenSSL integration via @cImport
- [ ] SSL context creation and certificate loading
- [ ] TLS handshake wrapping TCP streams
- [ ] HTTPS server mode (listen on port 443 / custom)
- [ ] SNI (Server Name Indication) support
- [ ] TLS 1.2 and 1.3 support
- [ ] Certificate auto-reload on file change
- [ ] Self-signed cert generation for development

---

## Phase 2: Router & Middleware Pipeline

### Router
- [x] Route definition types (method + path + handler) (`src/router/router.zig` — `RouteDef`)
- [x] Comptime route compilation (pattern -> segments at compile time) (`src/router/route.zig`)
- [x] Path parameter extraction (`:id`, `:slug`) (`src/router/route.zig` — `matchSegments`)
- [x] Wildcard path matching (`*path`) (`src/router/route.zig` — `Segment.wildcard`)
- [x] HTTP method dispatch (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS) (`src/router/router.zig`)
- [x] Route groups / scopes with shared middleware (`Router.scope()`)
- [ ] RESTful resource helper (auto-generates index/show/create/update/delete)
- [x] Nested route scopes (via `Router.scope()` prefix concatenation)
- [ ] Route naming for reverse URL generation
- [x] Comptime route validation (catch missing handlers at compile time)
- [x] 405 Method Not Allowed (path matches but wrong method, with `Allow` header)
- [ ] OPTIONS auto-response with allowed methods
- [x] HEAD auto-handling (GET without body)

### Middleware Pipeline
- [x] HandlerFn type (`*const fn (*Context) anyerror!void`) (`src/middleware/context.zig`)
- [x] Context struct (request + response + assigns + params + query) (`src/middleware/context.zig`)
- [x] Comptime middleware chain builder (`makePipelineEntry`/`makePipelineStep` in `router.zig`)
- [x] ctx.next() to call next middleware in chain
- [x] Assigns: fixed-size key-value store on context (like Phoenix conn.assigns)
- [x] Params: fixed-size key-value store for path params (zero-allocation)
- [x] Query string parsing into params

### Built-in Middleware
- [x] Logger middleware (method, path, status, timing) (`src/middleware/logger.zig`)
- [ ] Static file serving (directory, MIME detection, ETag, caching headers)
- [ ] CORS middleware (configurable origins, methods, headers)
- [ ] Body parser: JSON (application/json)
- [ ] Body parser: URL-encoded (application/x-www-form-urlencoded)
- [ ] Body parser: Multipart form data (file uploads)
- [ ] CSRF protection (token generation/validation)
- [ ] Session middleware (cookie-based, pluggable stores)
- [ ] gzip/deflate response compression
- [ ] Rate limiting (token bucket per IP/key)
- [ ] Auth: Bearer token extraction
- [ ] Auth: Basic auth
- [ ] Auth: JWT verification
- [ ] Global error handler middleware (catch panics, render error pages)

### Controller Helpers
- [x] json() response helper (`ctx.json()`)
- [x] html() response helper (`ctx.html()`)
- [x] text() response helper (`ctx.text()`)
- [x] respond() generic helper with content type (`ctx.respond()`)
- [ ] redirect() helper on Context
- [ ] send_file() for file downloads
- [ ] set_cookie() / delete_cookie()

---

## Phase 3: Template Engine

### Core Engine
- [ ] Template file format (.zzz or .html.zzz extension)
- [ ] Template lexer (tokenize template syntax)
- [ ] Template AST parser
- [ ] Comptime template compilation (templates -> Zig render functions)
- [ ] Build.zig integration (compile templates during build)
- [ ] Auto HTML escaping (XSS protection by default)
- [ ] Triple-brace {{{ }}} for raw/unescaped output

### Template Syntax
- [ ] Variable interpolation: `{{name}}`
- [ ] Dot notation: `{{user.name}}`
- [ ] Conditionals: `{{#if}}` / `{{else}}` / `{{/if}}`
- [ ] Iteration: `{{#each items as |item|}}` / `{{/each}}`
- [ ] With blocks: `{{#with user}}` / `{{/with}}`
- [ ] Comments: `{{! this is a comment }}`
- [ ] Raw blocks: `{{{{raw}}}}` (no processing)

### Layout System
- [ ] Layout templates with `{{yield}}` blocks
- [ ] Nested layouts
- [ ] Named yield blocks (header, footer, sidebar)
- [ ] Layout selection per controller/action

### Partials & Components
- [ ] Partial inclusion: `{{> partials/header}}`
- [ ] Partial with arguments: `{{> button type="primary"}}`
- [ ] Component blocks: `{{#component "card"}}...{{/component}}`
- [ ] Slot support for components

### Built-in Helpers
- [ ] `{{format_date date "YYYY-MM-DD"}}`
- [ ] `{{truncate text 100}}`
- [ ] `{{pluralize count "item" "items"}}`
- [ ] `{{url_for "user_path" id=user.id}}`
- [ ] Custom helper registration

### React/Vue SSR Bridge (Future)
- [ ] Shell out to Node/Deno/Bun for initial render
- [ ] Pass props as JSON, receive rendered HTML
- [ ] Hydration script injection
- [ ] Embedded QuickJS option for in-process JS

---

## Phase 4: WebSocket & Channels

### WebSocket Protocol
- [ ] RFC 6455 implementation
- [ ] HTTP -> WebSocket upgrade handshake
- [ ] Frame encoding (text, binary, ping, pong, close)
- [ ] Frame decoding with masking/unmasking
- [ ] Fragmented message reassembly
- [ ] Per-message compression (permessage-deflate)
- [ ] Ping/pong heartbeat keepalive
- [ ] Clean close handshake
- [ ] WebSocket URL routing

### Channel System (Phoenix-style)
- [ ] Channel definition (topic pattern + join/leave/handle_in)
- [ ] Topic-based PubSub (in-process)
- [ ] Channel join with authorization
- [ ] Incoming message handlers (event name -> handler)
- [ ] Broadcast to all subscribers of a topic
- [ ] Push messages to specific socket
- [ ] Channel reply messages
- [ ] Channel leave / disconnect handling
- [ ] Heartbeat monitoring per socket

### Presence
- [ ] Presence tracking (who's in which topic)
- [ ] Presence join/leave events
- [ ] Presence list with metadata
- [ ] Presence diff tracking (efficient updates)

### PubSub
- [ ] In-process PubSub (single node)
- [ ] Subscribe/unsubscribe to topics
- [ ] Broadcast to topic
- [ ] Direct message to specific subscriber
- [ ] Distributed PubSub (multi-node, future)

---

## Phase 5: Database Layer (zzz_db)

### Connection & Pooling
- [ ] Initialize zzz_db as separate package in workspace
- [ ] PostgreSQL adapter via libpq (@cImport)
- [ ] SQLite adapter via sqlite3 (@cImport)
- [ ] Connection pool (configurable size, checkout/checkin)
- [ ] Connection health checks
- [ ] Auto-reconnection on connection loss
- [ ] Connection timeout handling

### Schema Definition
- [ ] Comptime schema definition (struct -> table mapping)
- [ ] Field types mapping (Zig types -> SQL types)
- [ ] Primary key declaration
- [ ] Timestamps (inserted_at, updated_at) auto-fields
- [ ] has_many association
- [ ] belongs_to association
- [ ] has_one association
- [ ] many_to_many association (join table)
- [ ] Virtual/computed fields

### Query Builder
- [ ] SELECT builder with field selection
- [ ] WHERE clauses (=, !=, >, <, >=, <=, IN, LIKE, IS NULL)
- [ ] AND/OR composition
- [ ] ORDER BY (asc/desc, multiple fields)
- [ ] LIMIT / OFFSET
- [ ] JOIN (inner, left, right, full)
- [ ] GROUP BY / HAVING
- [ ] COUNT, SUM, AVG, MIN, MAX aggregates
- [ ] Subqueries
- [ ] Raw SQL fragments
- [ ] Query composition (pipe queries together)
- [ ] Preloading associations

### Repo Operations
- [ ] Repo.all(query) -> []T
- [ ] Repo.one(query) -> ?T
- [ ] Repo.get(Schema, id) -> ?T
- [ ] Repo.insert(changeset) -> T
- [ ] Repo.update(changeset) -> T
- [ ] Repo.delete(record) -> void
- [ ] Repo.aggregate(query, :count/:sum/etc)
- [ ] Repo.exists?(query) -> bool
- [ ] Repo.transaction(fn) -> result

### Changesets
- [ ] Changeset creation from params
- [ ] cast() - whitelist allowed fields
- [ ] validate_required() - required fields
- [ ] validate_format() - regex validation
- [ ] validate_length() - min/max string length
- [ ] validate_number() - min/max numeric range
- [ ] validate_inclusion() - value in list
- [ ] validate_exclusion() - value not in list
- [ ] unique_constraint() - database unique check
- [ ] foreign_key_constraint()
- [ ] custom validators
- [ ] Error messages (per field, per validation)
- [ ] Changeset.valid() -> bool

### Migrations
- [ ] Migration file format (up/down functions)
- [ ] create_table with column definitions
- [ ] alter_table (add/remove/rename columns)
- [ ] drop_table
- [ ] create_index / drop_index
- [ ] add_foreign_key / remove_foreign_key
- [ ] Migration runner (apply pending migrations)
- [ ] Migration rollback (revert last N migrations)
- [ ] Migration status tracking (schema_migrations table)
- [ ] Migration file generator

### Transactions
- [ ] Begin/commit/rollback
- [ ] Nested transactions (savepoints)
- [ ] Transaction isolation levels

---

## Phase 6: Background Jobs (zzz_jobs)

### Core
- [ ] Initialize zzz_jobs as separate package in workspace
- [ ] Job definition type (name, args struct, options)
- [ ] Job states: available -> executing -> completed / retryable / discarded
- [ ] Job insertion (enqueue)
- [ ] Scheduled jobs (run at specific time)
- [ ] Job priority levels

### Queue System
- [ ] In-memory queue (for dev/testing)
- [ ] Database-backed queue (uses zzz_db, for production)
- [ ] Named queues (e.g., "default", "mailers", "reports")
- [ ] Configurable concurrency per queue
- [ ] FIFO ordering within priority level
- [ ] Queue pausing/resuming

### Worker Management
- [ ] Worker thread pool
- [ ] Configurable worker count per queue
- [ ] Worker heartbeat monitoring
- [ ] Graceful shutdown (finish current jobs, stop accepting new)
- [ ] Worker crash recovery

### Retry & Error Handling
- [ ] Configurable max attempts per job
- [ ] Exponential backoff with jitter
- [ ] Custom retry strategies
- [ ] Dead letter queue (permanently failed jobs)
- [ ] Error callbacks / telemetry hooks
- [ ] Job timeout (kill long-running jobs)

### Scheduling (Cron)
- [ ] Cron expression parser
- [ ] Recurring job definitions
- [ ] Cron job registration at startup
- [ ] Timezone support

### Unique Jobs
- [ ] Unique constraints (prevent duplicate jobs)
- [ ] Unique by: args, queue, worker, period
- [ ] Replace strategy (cancel existing, ignore new)

### Telemetry
- [ ] Job start/complete/fail events
- [ ] Queue depth metrics
- [ ] Worker utilization metrics
- [ ] Job duration tracking

---

## Phase 7: Swagger / OpenAPI

### Schema Generation
- [ ] Comptime Zig struct -> JSON Schema conversion
- [ ] Type mapping (i32->integer, []const u8->string, bool->boolean, etc.)
- [ ] Optional type handling (?T -> nullable)
- [ ] Array type handling ([]T -> array)
- [ ] Nested struct handling (-> object)
- [ ] Enum -> enum schema

### Route Documentation
- [ ] Route annotation types (summary, description, tags)
- [ ] Path parameter schemas
- [ ] Query parameter schemas
- [ ] Request body schemas
- [ ] Response schemas (per status code)
- [ ] Auto-detection from handler function signatures (comptime)

### OpenAPI Spec Generation
- [ ] OpenAPI 3.0/3.1 JSON output
- [ ] Info section (title, version, description)
- [ ] Paths section (from router)
- [ ] Components/schemas section (from Zig types)
- [ ] Tags grouping
- [ ] Security schemes (Bearer, Basic, API key)
- [ ] Serve spec at configurable endpoint (e.g., /api/docs/openapi.json)

### Swagger UI
- [ ] Bundle Swagger UI static assets
- [ ] Serve Swagger UI at /api/docs
- [ ] Auto-configure with generated spec URL
- [ ] Development-only flag (disable in production)

---

## Phase 8: Testing Framework & CLI

### HTTP Test Client
- [ ] TestClient that sends requests to router without network
- [ ] GET/POST/PUT/PATCH/DELETE helpers
- [ ] Request header setting
- [ ] JSON body helper
- [ ] Multipart body helper (file upload testing)
- [ ] Response status assertions
- [ ] Response header assertions
- [ ] Response body assertions
- [ ] JSON path assertions ($.user.name)
- [ ] Cookie assertions
- [ ] Redirect following

### WebSocket Test Client
- [ ] TestWs.connect(router, path)
- [ ] Channel join/leave
- [ ] Push messages
- [ ] Expect reply with timeout
- [ ] Broadcast assertions

### Database Testing
- [ ] Test transaction sandboxing (auto-rollback per test)
- [ ] Parallel test execution support
- [ ] Factory/fixture helpers for test data
- [ ] Database seeding

### CLI Tool (zzz_cli)
- [ ] Initialize zzz_cli as separate package in workspace
- [ ] `zzz new my_app` - scaffold a new project
- [ ] `zzz server` - start development server with auto-reload
- [ ] `zzz routes` - list all registered routes
- [ ] `zzz migrate` - run pending migrations
- [ ] `zzz migrate.rollback` - rollback last migration
- [ ] `zzz migrate.status` - show migration status
- [ ] `zzz gen controller Name` - generate controller boilerplate
- [ ] `zzz gen model Name field:type` - generate model + migration
- [ ] `zzz gen channel Name` - generate channel boilerplate
- [ ] `zzz swagger` - generate/export OpenAPI spec
- [ ] `zzz test` - run tests with framework helpers
- [ ] `zzz deps` - manage dependencies

---

## Cross-Cutting Concerns

### Performance
- [ ] Benchmark suite (requests/sec, latency percentiles)
- [ ] Compare against other Zig frameworks (http.zig, zap, jetzig)
- [ ] Memory usage profiling
- [ ] Connection pooling optimization
- [ ] Zero-allocation hot paths

### Observability
- [ ] Structured logging (configurable levels, JSON output)
- [ ] Request ID generation and propagation
- [ ] Telemetry hooks (request start/end, DB query, job execution)
- [ ] Metrics collection (counters, histograms, gauges)
- [ ] Health check endpoint

### Documentation
- [ ] API reference (auto-generated from doc comments)
- [ ] Getting started guide
- [ ] Tutorial: building a blog
- [ ] Tutorial: building a REST API
- [ ] Tutorial: real-time chat with channels
- [ ] Deployment guide

### CI / Packaging
- [ ] GitHub Actions CI (build + test on Linux + macOS)
- [ ] Release builds for common targets
- [ ] Package published to Zig package index
- [ ] Docker image for deployment
- [ ] Example docker-compose with PostgreSQL

---

## Summary

| Phase | Status | Items Done | Items Remaining |
|-------|--------|------------|-----------------|
| 1. Foundation | **In Progress** | 14 | 10 |
| 1.5 TLS | Not Started | 0 | 8 |
| 2. Router & Middleware | **In Progress** | 20 | 16 |
| 3. Template Engine | Not Started | 0 | 28 |
| 4. WebSocket & Channels | Not Started | 0 | 22 |
| 5. Database (zzz_db) | Not Started | 0 | 49 |
| 6. Jobs (zzz_jobs) | Not Started | 0 | 27 |
| 7. Swagger | Not Started | 0 | 18 |
| 8. Testing & CLI | Not Started | 0 | 24 |
| Cross-Cutting | Not Started | 0 | 16 |
| **Total** | | **34** | **218** |
