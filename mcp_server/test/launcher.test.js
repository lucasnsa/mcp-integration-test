import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter, once } from 'node:events';
import { PassThrough } from 'node:stream';
import { createServer } from 'node:net';
import { AppLauncher } from '../src/launcher.js';

const options = {
  projectDir: '/tmp', device: 'emulator-5554',
  target: 'integration_test/mcp_test.dart', mode: 'run', adbForward: true,
};

async function listen(server, port = 0) {
  server.listen(port, '127.0.0.1');
  await once(server, 'listening');
  return server.address().port;
}

function fixture(t, { spawnError = false, removeError = false } = {}) {
  const calls = [];
  const forwards = new Map();
  const children = [];
  const launcher = new AppLauncher({
    async runCommand(command, args) {
      calls.push([command, ...args]);
      const port = Number(args[4].slice(4));
      if (args[3] === '--remove') {
        if (removeError) throw new Error('ADB unavailable');
        const server = forwards.get(port);
        assert.ok(server, 'only remove an owned forward');
        await new Promise((resolve) => server.close(resolve));
        forwards.delete(port);
      } else {
        assert.equal(args[3], '--no-rebind');
        const server = createServer();
        await listen(server, port);
        forwards.set(port, server);
      }
    },
    spawnProcess(command, args) {
      const child = new EventEmitter();
      child.stdout = new PassThrough();
      child.stderr = new PassThrough();
      child.stdin = new PassThrough();
      child.stdin.on('data', () => queueMicrotask(() => child.emit('exit', 0, null)));
      child.kill = () => child.emit('exit', null, 'SIGTERM');
      child.command = command;
      child.args = args;
      children.push(child);
      queueMicrotask(() => spawnError
        ? child.emit('error', new Error('spawn flutter ENOENT'))
        : child.emit('spawn'));
      return child;
    },
  });
  t.after(async () => {
    for (const server of forwards.values()) await new Promise((resolve) => server.close(resolve));
  });
  return { launcher, calls, forwards, children, allowRemoval: () => { removeError = false; } };
}

test('launch -> stop -> launch reuses an explicit port and removes the device forward', async (t) => {
  const { launcher, calls, forwards } = fixture(t);
  await launcher.start(options);
  const port = launcher.port;
  await launcher.stop();
  assert.equal(forwards.size, 0);
  assert.deepEqual(calls[1], ['adb', '-s', options.device, 'forward', '--remove', `tcp:${port}`]);
  await launcher.start({ ...options, port });
  assert.equal(launcher.port, port);
  await launcher.stop();
  await launcher.stop();
  assert.equal(calls.length, 4, 'repeated stop is harmless');
});

test('two launchers select different ports and stop independently', async (t) => {
  const a = fixture(t);
  const b = fixture(t);
  await a.launcher.start(options);
  await b.launcher.start({ ...options, device: 'emulator-5556' });
  assert.notEqual(a.launcher.port, b.launcher.port);
  for (const { launcher, children } of [a, b]) {
    assert.ok(children[0].args.includes(`--dart-define=MCP_IT_PORT=${launcher.port}`));
  }
  await a.launcher.stop();
  assert.equal(b.forwards.size, 1);
  assert.equal(b.launcher.running, true);
  await b.launcher.stop();
});

test('occupied explicit port fails before ADB or Flutter is invoked', async (t) => {
  const server = createServer();
  const port = await listen(server);
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const { launcher, calls, children } = fixture(t);
  await assert.rejects(launcher.start({ ...options, port }), new RegExp(`port ${port}.*EADDRINUSE`));
  assert.equal(calls.length, 0);
  assert.equal(children.length, 0);
});

test('stop cleans up even after the Flutter process exits', async (t) => {
  const { launcher, children, forwards } = fixture(t);
  await launcher.start(options);
  children[0].emit('exit', 1, null);
  assert.equal(launcher.running, false);
  await launcher.stop();
  assert.equal(forwards.size, 0);
});

test('spawn failure removes the forward', async (t) => {
  const { launcher, forwards } = fixture(t, { spawnError: true });
  await assert.rejects(launcher.start(options), /ENOENT/);
  assert.equal(forwards.size, 0);
  assert.equal(launcher.running, false);
});

test('failed ADB cleanup is reported and can be retried', async (t) => {
  const { launcher, forwards, allowRemoval } = fixture(t, { removeError: true });
  await launcher.start(options);
  await assert.rejects(launcher.stop(), /ADB unavailable/);
  assert.equal(forwards.size, 1);
  allowRemoval();
  await launcher.stop();
  assert.equal(forwards.size, 0);
});

test('launch without ADB never creates or removes forwards', async (t) => {
  const { launcher, calls } = fixture(t);
  await launcher.start({ ...options, adbForward: false });
  await launcher.stop();
  assert.deepEqual(calls, []);
});

test('rejected second launch preserves the running session', async (t) => {
  const { launcher, calls } = fixture(t);
  await launcher.start(options);
  const port = launcher.port;
  await assert.rejects(launcher.start(options), /already running/);
  assert.equal(launcher.port, port);
  assert.equal(calls.length, 1);
  await launcher.stop();
});
