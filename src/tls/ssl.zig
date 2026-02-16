const std = @import("std");

pub const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cInclude("openssl/crypto.h");
});

pub const SslError = error{
    SslContextCreationFailed,
    CertificateLoadFailed,
    PrivateKeyLoadFailed,
    SslObjectCreationFailed,
    SslHandshakeFailed,
};

/// Create a TLS server context with TLS 1.2+ and load cert/key files.
pub fn initSslContext(cert_path: [:0]const u8, key_path: [:0]const u8) SslError!*c.SSL_CTX {
    const method = c.TLS_server_method() orelse return error.SslContextCreationFailed;
    const ctx = c.SSL_CTX_new(method) orelse return error.SslContextCreationFailed;
    errdefer c.SSL_CTX_free(ctx);

    // Set minimum TLS version to 1.2
    if (c.SSL_CTX_set_min_proto_version(ctx, c.TLS1_2_VERSION) != 1) {
        return error.SslContextCreationFailed;
    }

    // Load certificate file
    if (c.SSL_CTX_use_certificate_file(ctx, cert_path.ptr, c.SSL_FILETYPE_PEM) != 1) {
        return error.CertificateLoadFailed;
    }

    // Load private key file
    if (c.SSL_CTX_use_PrivateKey_file(ctx, key_path.ptr, c.SSL_FILETYPE_PEM) != 1) {
        return error.PrivateKeyLoadFailed;
    }

    // Verify private key matches certificate
    if (c.SSL_CTX_check_private_key(ctx) != 1) {
        return error.PrivateKeyLoadFailed;
    }

    return ctx;
}

/// Free an SSL context.
pub fn deinitSslContext(ctx: *c.SSL_CTX) void {
    c.SSL_CTX_free(ctx);
}

/// Create an SSL object, attach to socket fd, and perform TLS handshake.
pub fn sslAccept(ctx: *c.SSL_CTX, fd: std.posix.fd_t) SslError!*c.SSL {
    const ssl = c.SSL_new(ctx) orelse return error.SslObjectCreationFailed;
    errdefer c.SSL_free(ssl);

    if (c.SSL_set_fd(ssl, fd) != 1) {
        return error.SslHandshakeFailed;
    }

    const ret = c.SSL_accept(ssl);
    if (ret != 1) {
        return error.SslHandshakeFailed;
    }

    return ssl;
}

/// Free an SSL object.
pub fn sslFree(ssl: *c.SSL) void {
    _ = c.SSL_shutdown(ssl);
    c.SSL_free(ssl);
}
