/**
 * Service client demonstrating modern JavaScript (ES2024+) syntax:
 * classes, private fields, async/await, destructuring, symbols, iterators.
 */

import { EventEmitter } from "node:events";
import { randomUUID } from "node:crypto";

// Constants
const MAX_RETRIES = 5;
const DEFAULT_TIMEOUT_MS = 30_000;
const CACHE_SIZE_LIMIT = 0xFF_FF;
const VERSION = "3.8.1";

/** @enum {string} Connection states */
const ConnectionState = Object.freeze({
  Connected: "connected",
  Connecting: "connecting",
  Disconnected: "disconnected",
});

const inspectSymbol = Symbol("inspect");

/**
 * Resilient service client with retry logic and connection pooling.
 * @extends EventEmitter
 */
export class ServiceClient extends EventEmitter {
  /** @type {string} */
  #baseUrl;
  #connectionState = ConnectionState.Disconnected;
  #requestCount = 0n;
  #cache = new Map();
  #activeTags = new Set(["default", "production"]);

  /**
   * @param {string} serviceName - Logical service identifier.
   * @param {Object} [options] - Client configuration.
   * @param {number} [options.port=8080] - Target port.
   * @param {number} [options.timeoutMs] - Request timeout in milliseconds.
   * @param {boolean} [options.compress=true] - Enable response compression.
   */
  constructor(serviceName, { port = 8080, timeoutMs, compress = true } = {}) {
    super();
    this.serviceName = serviceName;
    this.port = port;
    this.timeoutMs = timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.compress = compress;
    this.#baseUrl = `https://api.internal.io:${port}/v2`;
    this.correlationId = randomUUID();
  }

  get state() {
    return this.#connectionState;
  }

  get requestCount() {
    return this.#requestCount;
  }

  [inspectSymbol]() {
    return `ServiceClient<${this.serviceName}@${this.port}>`;
  }

  /**
   * Sends a request with automatic retry and exponential backoff.
   * @param {string} endpoint - API endpoint path.
   * @param {Object} [payload] - Request body.
   * @returns {Promise<Object>} Parsed response.
   */
  async request(endpoint, payload = null) {
    this.#connectionState = ConnectionState.Connecting;
    const url = `${this.#baseUrl}/${endpoint}`;

    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
      try {
        const response = await fetch(url, {
          method: payload ? "POST" : "GET",
          headers: {
            "Content-Type": "application/json",
            "X-Correlation-Id": this.correlationId,
            "X-Client-Version": VERSION,
            ...(this.compress && { "Accept-Encoding": "gzip, br" }),
          },
          body: payload ? JSON.stringify(payload) : undefined,
          signal: AbortSignal.timeout(this.timeoutMs),
        });

        if (!response.ok) {
          const status = response.status;
          const retryable = [429, 502, 503, 504].includes(status);
          if (!retryable || attempt === MAX_RETRIES) {
            throw new Error(`HTTP ${status}: ${response.statusText}`);
          }
          continue;
        }

        this.#connectionState = ConnectionState.Connected;
        this.#requestCount += 1n;
        const data = await response.json();

        // Cache successful GET responses
        if (!payload) {
          if (this.#cache.size >= CACHE_SIZE_LIMIT) {
            const [firstKey] = this.#cache.keys();
            this.#cache.delete(firstKey);
          }
          this.#cache.set(endpoint, { data, cachedAt: Date.now() });
        }

        this.emit("response", { endpoint, status: response.status, attempt });
        return data;
      } catch (err) {
        if (attempt === MAX_RETRIES) {
          this.#connectionState = ConnectionState.Disconnected;
          this.emit("error", { endpoint, message: err?.message ?? "Unknown error" });
          throw err;
        }
        const backoff = Math.min(100 * 2 ** attempt, 10_000);
        await new Promise((resolve) => setTimeout(resolve, backoff));
      }
    }
  }

  /**
   * Retrieves a cached response or fetches fresh data.
   * @param {string} endpoint
   * @param {number} [maxAgeMs=60000]
   */
  async cachedRequest(endpoint, maxAgeMs = 60_000) {
    const cached = this.#cache.get(endpoint);
    const isStale = !cached || Date.now() - cached.cachedAt > maxAgeMs;
    return isStale ? this.request(endpoint) : cached.data;
  }

  *[Symbol.iterator]() {
    for (const [key, { data, cachedAt }] of this.#cache) {
      yield { endpoint: key, data, age: Date.now() - cachedAt };
    }
  }

  static formatBytes(bytes) {
    const units = ["B", "KiB", "MiB", "GiB"];
    let idx = 0;
    let size = Number(bytes);
    while (size >= 1024 && idx < units.length - 1) {
      size /= 1024;
      idx++;
    }
    return `${size.toFixed(1)} ${units[idx]}`;
  }
}

// --- Usage ------------------------------------------------------------------

const client = new ServiceClient("telemetry", { port: 4318, compress: true });

client.on("response", ({ endpoint, status, attempt }) => {
  console.log(`[OK] ${endpoint} -> ${status} (attempt ${attempt})`);
});

client.on("error", ({ endpoint, message }) => {
  console.error(`[ERR] ${endpoint}: ${message}`);
});

const healthRegex = /^\/health[z]?$/i;

try {
  const result = await client.request("health");
  const isHealth = healthRegex.test("/healthz");
  console.log(`Health: ${JSON.stringify(result)}, matched: ${isHealth}`);
  console.log(`Requests: ${client.requestCount}, Cache: ${ServiceClient.formatBytes(1_048_576)}`);
} catch {
  process.exitCode = 1;
}
