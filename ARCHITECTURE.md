# Zzz - The Zig Web Framework That Never Sleeps

## Vision

A Phoenix-inspired, batteries-included web framework written in Zig from the ground up.
Blazing fast, memory-safe, with compile-time magic. Think Phoenix + Ecto + Oban, but in Zig.

---

## Project Structure (Monorepo in zigweb_workspace)

```
zigweb_workspace/
  zzz/                    # Core framework (this project)
    src/
      zzz.zig             # Public API / root module
      core/
        server.zig         # TCP server, connection handling
        tls.zig            # TLS via OpenSSL (HTTPS)
        http/
          request.zig      # HTTP request parsing
          response.zig     # HTTP response building
          headers.zig      # Header parsing/building
          parser.zig       # HTTP/1.1 protocol parser
          status.zig       # Status codes
          multipart.zig    # Multipart form parsing (uploads)
        websocket/
          frame.zig        # WebSocket frame encoding/decoding
          handler.zig      # WebSocket connection handler
          upgrade.zig      # HTTP -> WS upgrade
          channel.zig      # Phoenix-style channels (topic-based)
          presence.zig     # Presence tracking
      router/
        router.zig         # Comptime route tree builder
        route.zig          # Route definition types
        params.zig         # Path/query param extraction
        scope.zig          # Route scoping/nesting (like Phoenix scope/pipe_through)
        resource.zig       # RESTful resource routes
      middleware/
        middleware.zig     # Middleware chain (plug-like pipeline)
        static.zig         # Static file serving
        cors.zig           # CORS headers
        logger.zig         # Request logging
        auth.zig           # Auth helpers (Bearer, Basic, JWT)
        rate_limit.zig     # Rate limiting
        compress.zig       # gzip/deflate response compression
        csrf.zig           # CSRF protection
        session.zig        # Session management (cookie/store-backed)
        body_parser.zig    # JSON/form body parsing
        error_handler.zig  # Global error handler
      controller/
        controller.zig     # Controller base (conn-based like Phoenix)
        json.zig           # JSON response helpers
        html.zig           # HTML response helpers
        redirect.zig       # Redirect helpers
      template/
        engine.zig         # Template engine core
        compiler.zig       # Comptime template compilation
        lexer.zig          # Template lexer
        parser.zig         # Template AST parser
        runtime.zig        # Runtime rendering
        helpers.zig        # Built-in template helpers
        layout.zig         # Layout system
        partial.zig        # Partial/component system
        html_escape.zig    # XSS-safe escaping
      swagger/
        generator.zig      # OpenAPI spec generation from routes
        schema.zig         # JSON Schema from Zig types (comptime)
        ui.zig             # Swagger UI serving
        annotations.zig    # Route annotation types
      testing/
        test_client.zig    # HTTP test client (like Phoenix ConnTest)
        test_ws.zig        # WebSocket test helpers
        assertions.zig     # Custom test assertions
        mock_server.zig    # Mock server for testing
      io/
        event_loop.zig     # Event loop abstraction (kqueue/epoll/io_uring)
        kqueue.zig         # macOS/BSD backend
        epoll.zig          # Linux backend
        io_uring.zig       # Linux io_uring backend
        thread_pool.zig    # Worker thread pool
      utils/
        json.zig           # JSON helpers (std.json wrapper)
        url.zig            # URL parsing/encoding
        mime.zig           # MIME type detection
        crypto.zig         # Hashing, HMAC, token generation
        time.zig           # Time/date helpers
        pool.zig           # Generic object pool
        ring_buffer.zig    # Ring buffer for connections
    build.zig
    build.zig.zon

  zzz_db/                  # Database/ORM package (like Ecto)
    src/
      zzz_db.zig           # Public API
      connection/
        pool.zig           # Connection pool
        conn.zig           # Single connection wrapper
      adapters/
        postgres.zig       # PostgreSQL adapter (via libpq)
        sqlite.zig         # SQLite adapter (via C lib)
        mysql.zig          # MySQL adapter (via C lib)
      query/
        builder.zig        # Query builder (composable, like Ecto.Query)
        select.zig         # SELECT builder
        insert.zig         # INSERT builder
        update.zig         # UPDATE builder
        delete.zig         # DELETE builder
        join.zig           # JOIN support
        fragment.zig       # Raw SQL fragments
        expr.zig           # Expression tree
      schema/
        schema.zig         # Schema definition (comptime struct -> table mapping)
        field.zig          # Field types and options
        association.zig    # has_many, belongs_to, many_to_many
        changeset.zig      # Changeset validation/casting (like Ecto.Changeset)
        validator.zig      # Built-in validators
      migration/
        migration.zig      # Migration system
        runner.zig         # Migration runner (up/down)
        generator.zig      # Migration file generator
        schema_diff.zig    # Schema diff for auto-migration
      repo.zig             # Repo pattern (like Ecto.Repo)
      transaction.zig      # Transaction support
    build.zig
    build.zig.zon

  zzz_jobs/                # Background job system (like Oban)
    src/
      zzz_jobs.zig         # Public API
      queue/
        queue.zig          # Job queue abstraction
        memory_queue.zig   # In-memory queue (dev/testing)
        db_queue.zig       # Database-backed queue (production)
      worker.zig           # Worker process/thread
      scheduler.zig        # Job scheduler (cron-like)
      job.zig              # Job definition type
      retry.zig            # Retry strategies (exponential backoff, etc.)
      supervisor.zig       # Worker supervisor (restart on failure)
      telemetry.zig        # Job telemetry/metrics
      unique.zig           # Unique job constraints
    build.zig
    build.zig.zon

  zzz_cli/                 # CLI tools (like mix phx.*)
    src/
      main.zig             # CLI entry point
      commands/
        new.zig            # zzz new my_app
        server.zig         # zzz server (start dev server)
        routes.zig         # zzz routes (list all routes)
        migrate.zig        # zzz migrate (run migrations)
        generate.zig       # zzz gen controller/model/...
        swagger.zig        # zzz swagger (generate OpenAPI spec)
        test.zig           # zzz test (run tests with helpers)
    build.zig
    build.zig.zon

  example_app/             # Sample Phoenix-like application
    src/
      main.zig             # Application entry
      router.zig           # App router
      controllers/
        page_controller.zig
        user_controller.zig
        api/
          v1/
            user_controller.zig
      models/
        user.zig
        post.zig
      templates/
        layout/
          app.html.zzz
        page/
          index.html.zzz
          about.html.zzz
        user/
          index.html.zzz
          show.html.zzz
          form.html.zzz
      static/
        css/
        js/
        images/
      jobs/
        email_job.zig
        cleanup_job.zig
      migrations/
        001_create_users.zig
        002_create_posts.zig
    build.zig
    build.zig.zon
```

---

## Component Architecture & Implementation Plan

### Phase 1: Foundation (TCP Server + HTTP/1.1)

**Goal**: Accept TCP connections, parse HTTP, send responses.

#### 1.1 Event Loop / I/O Layer
- **Build ourselves**: Platform-specific event loop abstraction
- **kqueue** on macOS (your dev machine)
- **epoll** on Linux (production)
- **io_uring** on Linux 5.1+ (optional high-perf path)
- Non-blocking I/O with worker thread pool
- Connection state machine: Accept -> Read -> Process -> Write -> Close/KeepAlive

#### 1.2 TCP Server
- Bind/listen on address:port
- Accept connections via event loop
- Connection pool with configurable limits
- Graceful shutdown

#### 1.3 HTTP Parser
- **Build ourselves**: Zero-copy HTTP/1.1 parser
- Parse request line (method, path, version)
- Parse headers (zero-alloc where possible, use slices into read buffer)
- Handle chunked transfer encoding
- Content-Length body reading
- Keep-alive connection management
- Pipelining support

#### 1.4 HTTP Response Builder
- Status line + headers + body
- Streaming response support
- Chunked encoding for streaming
- Content-Type detection

#### 1.5 TLS (HTTPS)
- **Use OpenSSL** via @cImport
- SSL context setup, certificate loading
- TLS handshake wrapping the TCP connection
- SNI support for virtual hosts

**Deliverable**: `zig build run` starts a server that responds to `curl http://localhost:8080/`

---

### Phase 2: Router & Middleware Pipeline

**Goal**: Route requests to handlers through a middleware chain.

#### 2.1 Router (Comptime)
- **Build ourselves**: Radix tree router compiled at comptime
- Path matching: `/users/:id`, `/files/*path` (wildcard)
- HTTP method dispatch: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
- Route groups/scopes with shared middleware:
  ```zig
  const router = Router.define(.{
      .scope("/api/v1", .{ .pipe = .{api_auth, json_parser} }, .{
          .get("/users", UserController.index),
          .get("/users/:id", UserController.show),
          .post("/users", UserController.create),
          .resources("/posts", PostController),
      }),
      .scope("/", .{ .pipe = .{browser_session, csrf} }, .{
          .get("/", PageController.index),
          .get("/about", PageController.about),
      }),
  });
  ```
- RESTful resource helper (generates index/show/create/update/delete routes)
- Comptime route validation (catch typos, missing handlers at compile time)

#### 2.2 Middleware Pipeline (Plug-like)
- **Build ourselves**: Ordered chain of transforms on Request -> Response
- Each middleware is a struct with `call(ctx: *Context) !Action` where Action is `.next` or `.halt`
- Context carries: request, response, assigns (typed map), connection state
- Built-in middleware:
  - **Logger**: Request timing, method, path, status
  - **Static**: Serve files from a directory with MIME detection, ETag, caching headers
  - **BodyParser**: JSON (`application/json`) and form (`application/x-www-form-urlencoded`, `multipart/form-data`)
  - **CORS**: Configurable origin, methods, headers
  - **CSRF**: Token generation/validation
  - **Session**: Cookie-based sessions with pluggable stores (memory, DB)
  - **Compress**: gzip/deflate based on Accept-Encoding
  - **RateLimit**: Token bucket per IP/key
  - **Auth**: Bearer token extraction, Basic auth, JWT verification
  - **ErrorHandler**: Catch errors, render error pages/JSON

#### 2.3 Connection / Context
- Request + Response + metadata in one struct
- `assigns`: typed key-value store (like Phoenix conn.assigns)
- `params`: merged path + query + body params
- Helper methods: `json()`, `html()`, `redirect()`, `send_file()`, `text()`

**Deliverable**: Routes dispatch to handlers, middleware processes requests/responses.

---

### Phase 3: Template Engine

**Goal**: Compile templates to Zig functions at build time.

#### 3.1 Template Syntax (Handlebars-inspired with Zig power)
```html
{{! comment }}
<h1>Hello, {{name}}!</h1>

{{#if user}}
  <p>Welcome back, {{user.name}}</p>
{{else}}
  <p>Please log in</p>
{{/if}}

{{#each users as |user|}}
  <li>{{user.name}} - {{user.email}}</li>
{{/each}}

{{> partials/header}}

{{#component "button" type="primary"}}
  Click me
{{/component}}

{{{raw_html}}}  {{! triple-brace = unescaped }}
```

#### 3.2 Comptime Compilation
- Parse templates at `comptime` in build.zig
- Generate Zig render functions that write to a Writer
- Auto HTML-escape by default (XSS protection)
- Partials resolved and inlined at compile time
- Layout wrapping (yield block)
- Zero runtime template parsing overhead

#### 3.3 React/Vue SSR Bridge (Later Phase)
- Shell out to Node/Deno/Bun for initial render
- Pass props as JSON
- Return rendered HTML string
- Hydration script injection
- Could also embed QuickJS for in-process JS execution

**Deliverable**: `{{name}}` templates compile to fast Zig render functions.

---

### Phase 4: WebSocket & Channels

**Goal**: Full WebSocket support with Phoenix-style channels.

#### 4.1 WebSocket Protocol
- **Build ourselves**: RFC 6455 implementation
- HTTP upgrade handshake
- Frame encoding/decoding (text, binary, ping/pong, close)
- Masking/unmasking
- Fragmented messages
- Per-message compression (permessage-deflate)

#### 4.2 Channel System (Phoenix-style)
```zig
const ChatChannel = Channel.define("room:*", .{
    .join = struct {
        fn handle(socket: *Socket, topic: []const u8, params: anytype) !JoinResult {
            // authorize join
            return .{ .ok = .{} };
        }
    }.handle,
    .handle_in = &.{
        .{ "new_msg", handleNewMsg },
        .{ "typing", handleTyping },
    },
    .handle_info = handleInfo,
    .terminate = terminate,
});
```
- Topic-based PubSub (in-process, expandable to distributed)
- Broadcast to all subscribers of a topic
- Presence tracking (who's in which room)
- Heartbeat/keepalive

**Deliverable**: WebSocket chat demo with channels and presence.

---

### Phase 5: Database Layer (zzz_db)

**Goal**: Ecto-like database toolkit.

#### 5.1 Connection & Pooling
- **Use libpq** (PostgreSQL C library) via @cImport
- **Use sqlite3** C library for SQLite
- Connection pool with configurable size
- Health checks, reconnection

#### 5.2 Schema Definition (Comptime)
```zig
const User = Schema.define("users", struct {
    id: i64,
    name: []const u8,
    email: []const u8,
    age: ?i32 = null,
    inserted_at: Timestamp,
    updated_at: Timestamp,
}, .{
    .primary_key = .id,
    .has_many = .{ .posts = Post },
    .has_one = .{ .profile = Profile },
    .timestamps = true,
});
```

#### 5.3 Query Builder
```zig
// Composable queries
const query = User.query()
    .where(.{ .age = .{ .gte = 18 } })
    .where(.{ .active = true })
    .join(.inner, .posts)
    .select(.{ .name, .email, .posts })
    .order_by(.{ .inserted_at = .desc })
    .limit(10)
    .offset(20);

const users = try Repo.all(query);
const user = try Repo.one(query);  // returns ?User
const count = try Repo.aggregate(query, .count);
```

#### 5.4 Changesets
```zig
const changeset = User.changeset(params)
    .cast(.{ .name, .email, .age })
    .validate_required(.{ .name, .email })
    .validate_format(.email, regex("^[^@]+@[^@]+$"))
    .validate_length(.name, .{ .min = 2, .max = 100 })
    .validate_number(.age, .{ .gte = 0, .lte = 150 })
    .unique_constraint(.email);

if (changeset.valid()) {
    const user = try Repo.insert(changeset);
} else {
    // changeset.errors has validation errors
}
```

#### 5.5 Migrations
```zig
pub fn up(m: *Migration) !void {
    try m.create_table("users", .{
        .{ .name = "id", .type = .bigserial, .primary_key = true },
        .{ .name = "name", .type = .varchar, .size = 255, .null = false },
        .{ .name = "email", .type = .varchar, .size = 255, .null = false },
        .{ .name = "age", .type = .integer, .null = true },
    });
    try m.create_index("users", .{.email}, .{ .unique = true });
}

pub fn down(m: *Migration) !void {
    try m.drop_table("users");
}
```

#### 5.6 Transactions
```zig
try Repo.transaction(struct {
    fn run(repo: *Repo) !void {
        const user = try repo.insert(user_changeset);
        const profile = try repo.insert(profile_changeset);
        try repo.insert(log_changeset);
    }
}.run);
```

**Deliverable**: CRUD operations with PostgreSQL, migrations, changesets.

---

### Phase 6: Background Jobs (zzz_jobs)

**Goal**: Oban-like reliable background job processing.

#### 6.1 Job Definition
```zig
const EmailJob = Job.define("email", struct {
    to: []const u8,
    subject: []const u8,
    body: []const u8,
}, .{
    .queue = "mailers",
    .max_attempts = 5,
    .priority = 1,
    .unique = .{ .period = 300, .fields = .{.to, .subject} },
});

// Enqueue
try Jobs.insert(EmailJob, .{
    .to = "user@example.com",
    .subject = "Welcome!",
    .body = "Hello...",
});

// Schedule for later
try Jobs.insert(EmailJob, .{...}, .{ .scheduled_at = now.add(.minutes, 30) });
```

#### 6.2 Queue System
- **Database-backed** (uses zzz_db) for persistence/reliability
- **In-memory** option for dev/testing
- Job states: available -> executing -> completed / retryable / discarded
- FIFO with priority support
- Unique job constraints (prevent duplicates)

#### 6.3 Worker Management
- Configurable worker count per queue
- Thread pool for concurrent job execution
- Graceful shutdown (finish current jobs)
- Heartbeat monitoring

#### 6.4 Scheduling (Cron)
```zig
const schedule = Scheduler.define(.{
    .{ "0 * * * *", CleanupJob },      // Every hour
    .{ "0 0 * * *", ReportJob },        // Daily at midnight
    .{ "*/5 * * * *", HealthCheckJob }, // Every 5 minutes
});
```

#### 6.5 Retry & Error Handling
- Exponential backoff with jitter
- Configurable max attempts
- Dead letter queue for permanently failed jobs
- Error callbacks/telemetry

**Deliverable**: Enqueue jobs, process them in background threads, retry on failure.

---

### Phase 7: Swagger / OpenAPI

**Goal**: Auto-generate API documentation from route definitions.

#### 7.1 Schema Generation (Comptime)
- Reflect on Zig structs to generate JSON Schema at comptime
- Map Zig types to OpenAPI types:
  - `i32/i64` -> integer
  - `f32/f64` -> number
  - `[]const u8` -> string
  - `bool` -> boolean
  - `?T` -> nullable
  - `[]T` -> array
  - Structs -> object with properties

#### 7.2 Route Annotations
```zig
.get("/users/:id", UserController.show, .{
    .summary = "Get a user by ID",
    .tags = .{"Users"},
    .params = .{
        .id = .{ .type = i64, .description = "User ID" },
    },
    .response = .{
        .@"200" = .{ .schema = User, .description = "Success" },
        .@"404" = .{ .description = "User not found" },
    },
}),
```

#### 7.3 Swagger UI
- Serve Swagger UI static assets
- Serve generated OpenAPI JSON at `/api/docs/openapi.json`
- Available at `/api/docs` in development

**Deliverable**: Auto-generated OpenAPI spec + Swagger UI at `/api/docs`.

---

### Phase 8: Testing Framework

**Goal**: First-class testing support for web apps.

#### 8.1 HTTP Test Client
```zig
const t = TestClient.init(router);

// Test a GET request
const resp = try t.get("/users/1")
    .header("Authorization", "Bearer token123")
    .expect_status(200)
    .expect_json_path("$.name", "John")
    .perform();

// Test a POST request
const resp2 = try t.post("/users")
    .json(.{ .name = "Jane", .email = "jane@example.com" })
    .expect_status(201)
    .perform();

// Test file upload
const resp3 = try t.post("/upload")
    .multipart(.{
        .file = .{ .path = "test.png", .content_type = "image/png" },
        .description = "A test image",
    })
    .expect_status(200)
    .perform();
```

#### 8.2 WebSocket Test Client
```zig
const ws = try TestWs.connect(router, "/ws");
try ws.join("room:lobby", .{});
try ws.push("new_msg", .{ .body = "hello" });
const reply = try ws.expect_reply("new_msg");
try std.testing.expectEqualStrings("hello", reply.body);
```

#### 8.3 Database Sandboxing
- Each test runs in a transaction that rolls back
- Parallel test execution without conflicts
- Factory/fixture helpers

**Deliverable**: `zig build test` runs full HTTP integration tests.

---

## What We Build vs. What We Use (Libraries)

### Build Ourselves (Core Competency)
| Component | Reason |
|-----------|--------|
| HTTP parser | Zero-copy, no allocations, Zig-idiomatic |
| Router | Comptime radix tree, no runtime overhead |
| Middleware pipeline | Comptime chain, type-safe |
| Template engine | Comptime compilation, zero runtime parsing |
| WebSocket protocol | RFC 6455, tight integration with server |
| Query builder | Comptime type reflection, Zig-native |
| Changeset/validation | Comptime field introspection |
| Job queue | Tight integration with zzz_db |
| Swagger generator | Comptime type reflection |
| Event loop | Platform-specific (kqueue/epoll/io_uring) |
| Connection pool | Generic, used by both HTTP and DB |

### Use C Libraries (via @cImport)
| Library | Purpose |
|---------|---------|
| OpenSSL (libssl, libcrypto) | TLS/HTTPS, crypto primitives |
| libpq | PostgreSQL wire protocol |
| sqlite3 | SQLite database |
| zlib | gzip/deflate compression |

### Optional/Future C Libraries
| Library | Purpose |
|---------|---------|
| QuickJS / libv8 | In-process JS for React SSR |
| libmysqlclient | MySQL support |
| libcurl | HTTP client (for testing, webhooks) |

---

## Implementation Order (Recommended)

```
Phase 1 ──> Phase 2 ──> Phase 3 ──────────> Phase 7
  |            |           |                    |
  |            |           v                    v
  |            |       Phase 4              Phase 8
  |            |                               ^
  |            v                               |
  |        Phase 5 ──> Phase 6 ───────────────-┘
  v
[Everything builds on TCP/HTTP foundation]
```

### Milestone Targets

1. **M1 - Hello World Server**: TCP + HTTP parser + basic response (Phase 1)
2. **M2 - Routed App**: Router + middleware + static files (Phase 2)
3. **M3 - Templated App**: Template engine + layouts + forms (Phase 3)
4. **M4 - Real-time**: WebSocket + channels + presence (Phase 4)
5. **M5 - Data Layer**: PostgreSQL + queries + migrations (Phase 5)
6. **M6 - Background Processing**: Job queue + scheduler (Phase 6)
7. **M7 - API Docs**: Swagger/OpenAPI generation (Phase 7)
8. **M8 - Full Stack**: Example app + test suite + CLI (Phase 8)

---

## Key Design Principles

1. **Comptime Everything**: Routes, middleware chains, templates, schemas - all resolved at compile time
2. **Zero-Copy Parsing**: HTTP parser uses slices into read buffers, no allocations for headers
3. **Explicit Allocators**: Every allocation site takes an allocator parameter (Zig convention)
4. **No Hidden Control Flow**: No exceptions, no hidden allocations, errors are values
5. **Layered Architecture**: Each component usable standalone (just the router, just the DB, etc.)
6. **Type Safety**: Comptime type introspection for schemas, params, responses
7. **Fail at Compile Time**: Catch as many errors as possible during compilation
8. **Convention over Configuration**: Sensible defaults, override when needed
