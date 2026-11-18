/** Thin JSON-RPC client for the server embedded in the Flutter app. */
export class AppClient {
  constructor(baseUrl) {
    this.baseUrl = baseUrl;
  }

  async health(timeoutMs = 1500) {
    try {
      const res = await fetch(`${this.baseUrl}/health`, { signal: AbortSignal.timeout(timeoutMs) });
      return res.ok;
    } catch {
      return false;
    }
  }

  /** Sends one command; resolves with `result`, rejects with the app's error. */
  async call(method, params = {}, timeoutMs = 60_000) {
    let res;
    try {
      res = await fetch(`${this.baseUrl}/rpc`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ method, params }),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (e) {
      throw new Error(
        `Cannot reach the app at ${this.baseUrl} (${e.cause?.code ?? e.name}). ` +
          `Is the MCP test build running? Use app_launch, or start it manually and call app_connect.`,
      );
    }
    const body = await res.json();
    if (!body.ok) throw new Error(body.error ?? `HTTP ${res.status}`);
    return body;
  }
}
