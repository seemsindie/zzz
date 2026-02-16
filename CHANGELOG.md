# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-16

### Added
- HTTP/1.1 server with optional TLS/HTTPS (OpenSSL)
- Compile-time router with path params, query params, scoping, and RESTful resources
- Controller module for grouping routes with shared middleware
- 20 built-in middleware: logger, CORS, compression, auth (Bearer/Basic/JWT), rate limiting, CSRF, sessions, body parser, static files, error handler, request ID, structured logger, telemetry, metrics, health check, htmx, WebSocket, channel, zzz.js
- WebSocket support with frame encoding/decoding and HTTP upgrade
- Phoenix-style channels with topic-based pub/sub and presence tracking
- zzz.js client library for WebSocket and channel communication
- Template engine with layouts, partials, and XSS-safe HTML escaping
- OpenAPI/Swagger spec generation with security schemes and Swagger UI
- Testing utilities (HTTP test client, WebSocket helpers, assertions)
- High-performance I/O backends (epoll, kqueue, io_uring)
- GitHub Actions CI (Linux + macOS)
