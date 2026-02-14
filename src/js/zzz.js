/**
 * zzz.js — Client-side library for the Zzz web framework.
 *
 * Provides WebSocket with auto-reconnect, fetch wrapper, and form submission helper.
 */
const Zzz = {
  /**
   * Connect to a WebSocket endpoint with auto-reconnect and exponential backoff.
   *
   * @param {string} url - WebSocket URL (e.g., "ws://localhost:9000/ws/echo")
   * @param {object} opts - Options
   * @param {number} opts.maxRetries - Max reconnect attempts (default: 10)
   * @param {number} opts.baseDelay - Base delay in ms for backoff (default: 1000)
   * @param {number} opts.maxDelay - Max delay in ms (default: 30000)
   * @returns {{ send, on, close, readyState }}
   */
  connect(url, opts = {}) {
    const maxRetries = opts.maxRetries ?? 10;
    const baseDelay = opts.baseDelay ?? 1000;
    const maxDelay = opts.maxDelay ?? 30000;

    const listeners = { open: [], message: [], close: [], error: [] };
    let ws = null;
    let retries = 0;
    let intentionalClose = false;

    function emit(event, data) {
      (listeners[event] || []).forEach(fn => fn(data));
    }

    function createWs() {
      ws = new WebSocket(url);

      ws.onopen = () => {
        retries = 0;
        emit("open", ws);
      };

      ws.onmessage = (e) => {
        emit("message", e.data);
      };

      ws.onclose = (e) => {
        emit("close", { code: e.code, reason: e.reason });
        if (!intentionalClose && retries < maxRetries) {
          const delay = Math.min(baseDelay * Math.pow(2, retries), maxDelay);
          retries++;
          setTimeout(createWs, delay);
        }
      };

      ws.onerror = (e) => {
        emit("error", e);
      };
    }

    createWs();

    return {
      send(data) { if (ws && ws.readyState === WebSocket.OPEN) ws.send(data); },
      on(event, fn) { if (listeners[event]) listeners[event].push(fn); },
      close(code, reason) { intentionalClose = true; if (ws) ws.close(code || 1000, reason || ""); },
      get readyState() { return ws ? ws.readyState : WebSocket.CLOSED; },
    };
  },

  /**
   * Fetch wrapper with auto CSRF token from <meta name="csrf-token">.
   *
   * @param {string} url - Request URL
   * @param {object} opts - fetch() options, plus `json` shorthand for JSON body
   * @returns {Promise<Response>}
   */
  async fetch(url, opts = {}) {
    const headers = new Headers(opts.headers || {});

    // Auto-attach CSRF token for non-GET requests
    const method = (opts.method || "GET").toUpperCase();
    if (method !== "GET" && method !== "HEAD") {
      const meta = document.querySelector('meta[name="csrf-token"]');
      if (meta) {
        headers.set("X-CSRF-Token", meta.getAttribute("content"));
      }
    }

    // JSON shorthand
    if (opts.json !== undefined) {
      headers.set("Content-Type", "application/json");
      opts.body = JSON.stringify(opts.json);
      delete opts.json;
    }

    opts.headers = headers;
    return fetch(url, opts);
  },

  /**
   * Submit a form via AJAX (FormData), with auto CSRF.
   *
   * @param {HTMLFormElement|string} form - Form element or CSS selector
   * @param {object} opts - Additional fetch options
   * @returns {Promise<Response>}
   */
  async formSubmit(form, opts = {}) {
    const el = typeof form === "string" ? document.querySelector(form) : form;
    if (!el) throw new Error("Form not found");

    const method = (el.method || "POST").toUpperCase();
    const action = el.action || window.location.href;
    const body = new FormData(el);

    return Zzz.fetch(action, { method, body, ...opts });
  },
};

if (typeof module !== "undefined" && module.exports) {
  module.exports = Zzz;
}
