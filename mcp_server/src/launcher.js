import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createServer } from 'node:net';

const execFileP = promisify(execFile);
const MAX_LOG_LINES = 500;

/** Ask the OS for a free loopback port, or check an explicitly requested port. */
async function selectPort(port) {
  if (port !== undefined && (!Number.isInteger(port) || port < 1 || port > 65535)) {
    throw new Error('Port must be an integer between 1 and 65535.');
  }
  const server = createServer();
  await new Promise((resolve, reject) => {
    server.once('error', (error) => reject(new Error(
      `Cannot use local port ${port ?? 'automatically selected'} (${error.code}). ` +
      'Choose another port or omit port to select a free one.',
    )));
    server.listen(port ?? 0, '127.0.0.1', resolve);
  });
  const selected = server.address().port;
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  return selected;
}

/** Owns the `flutter run` / `flutter test` child process. */
export class AppLauncher {
  constructor({ spawnProcess = spawn, runCommand = execFileP } = {}) {
    this.spawnProcess = spawnProcess;
    this.runCommand = runCommand;
    this.child = null;
    this.logs = [];
    this.exit = null;
    this.port = null;
    this.forward = null;
  }

  get running() {
    return this.child !== null && this.exit === null;
  }

  #log(chunk, tag) {
    for (const line of chunk.toString().split('\n')) {
      if (line.trim()) this.logs.push(`${tag}${line}`);
    }
    if (this.logs.length > MAX_LOG_LINES) this.logs.splice(0, this.logs.length - MAX_LOG_LINES);
  }

  /**
   * mode "run":  flutter run -t <target>   (debuggable, hot reload possible)
   * mode "test": flutter test <target>     (official integration_test flow;
   *              exit code reflects failed expectations)
   */
  async start({ projectDir, device, target, mode, port, dartDefines = [], extraArgs = [], adbForward }) {
    if (this.running) throw new Error('An app is already running. Call app_stop first.');
    await this.stop();
    port = await selectPort(port);
    if (adbForward) {
      // Do not replace a mapping owned by another session if port selection races.
      await this.runCommand('adb', ['-s', device, 'forward', '--no-rebind', `tcp:${port}`, `tcp:${port}`]);
      this.forward = { device, port };
    }
    this.port = port;
    const defines = [`MCP_IT_PORT=${port}`, ...dartDefines].map((d) => `--dart-define=${d}`);
    const args =
      mode === 'test'
        ? ['test', target, '-d', device, ...defines, ...extraArgs]
        : ['run', '-d', device, '-t', target, ...defines, ...extraArgs];
    this.logs = [];
    this.exit = null;
    try {
      this.child = this.spawnProcess('flutter', args, { cwd: projectDir, stdio: ['pipe', 'pipe', 'pipe'] });
      this.child.stdout.on('data', (d) => this.#log(d, ''));
      this.child.stderr.on('data', (d) => this.#log(d, '[stderr] '));
      this.child.on('error', (e) => {
        this.exit = { error: e.message };
        this.#log(e.message, '[spawn] ');
      });
      this.child.on('exit', (code, signal) => {
        this.exit = { code, signal };
      });
      await new Promise((resolve, reject) => {
        this.child.once('spawn', resolve);
        this.child.once('error', reject);
      });
    } catch (error) {
      this.child = null;
      await this.#removeForward();
      throw error;
    }
    return `flutter ${args.join(' ')}`;
  }

  async #removeForward() {
    if (!this.forward) return;
    const { device, port } = this.forward;
    await this.runCommand('adb', ['-s', device, 'forward', '--remove', `tcp:${port}`]);
    this.forward = null;
  }

  async stop() {
    try {
      if (!this.child) return;
      const child = this.child;
      if (this.running) {
        await new Promise((resolve) => {
          const t = setTimeout(() => {
            child.kill('SIGTERM');
            resolve();
          }, 5000);
          child.once('exit', () => {
            clearTimeout(t);
            resolve();
          });
          if (child.stdin.writable) child.stdin.write('q', () => {}); // graceful quit for `flutter run`
        });
      }
      this.child = null;
    } finally {
      await this.#removeForward();
    }
  }
}
