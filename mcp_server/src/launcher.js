import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileP = promisify(execFile);
const MAX_LOG_LINES = 500;

/** Owns the `flutter run` / `flutter test` child process. */
export class AppLauncher {
  constructor() {
    this.child = null;
    this.logs = [];
    this.exit = null;
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
    if (adbForward) {
      await execFileP('adb', ['-s', device, 'forward', `tcp:${port}`, `tcp:${port}`]);
    }
    const defines = [`MCP_IT_PORT=${port}`, ...dartDefines].map((d) => `--dart-define=${d}`);
    const args =
      mode === 'test'
        ? ['test', target, '-d', device, ...defines, ...extraArgs]
        : ['run', '-d', device, '-t', target, ...defines, ...extraArgs];
    this.logs = [];
    this.exit = null;
    this.child = spawn('flutter', args, { cwd: projectDir, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stdout.on('data', (d) => this.#log(d, ''));
    this.child.stderr.on('data', (d) => this.#log(d, '[stderr] '));
    this.child.on('error', (e) => {
      this.exit = { error: e.message };
      this.#log(e.message, '[spawn] ');
    });
    this.child.on('exit', (code, signal) => {
      this.exit = { code, signal };
    });
    return `flutter ${args.join(' ')}`;
  }

  async stop() {
    if (!this.child) return;
    const child = this.child;
    if (this.running) {
      child.stdin.write('q'); // graceful quit for `flutter run`
      await new Promise((resolve) => {
        const t = setTimeout(() => {
          child.kill('SIGTERM');
          resolve();
        }, 5000);
        child.once('exit', () => {
          clearTimeout(t);
          resolve();
        });
      });
    }
    this.child = null;
  }
}
