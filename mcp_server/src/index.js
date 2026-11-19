#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { AppClient } from './client.js';
import { AppLauncher } from './launcher.js';
import { loadEnvFile } from './env.js';

const DEFAULT_PORT = Number(process.env.MCP_IT_PORT ?? 8765);
let client = new AppClient(process.env.MCP_IT_URL ?? `http://127.0.0.1:${DEFAULT_PORT}`);
const launcher = new AppLauncher();
/** dotenv file with test data; read here so secret values never reach the client. */
const ENV_FILE = process.env.MCP_IT_ENV_FILE;

const server = new McpServer({ name: 'flutter-integration-test', version: '0.1.0' });

// --- helpers -----------------------------------------------------------

const text = (value) => ({
  content: [{ type: 'text', text: typeof value === 'string' ? value : JSON.stringify(value, null, 2) }],
});
const fail = (e) => ({ isError: true, content: [{ type: 'text', text: e.message ?? String(e) }] });

/** Width of evidence screenshots taken through `shot` (logical width of a smartPOS). */
const SHOT_WIDTH = Number(process.env.MCP_IT_SHOT_WIDTH ?? 360);

const shotFields = {
  shot: z
    .string()
    .optional()
    .describe('Absolute .png path: after the action, save a screenshot there (evidence) in the same call'),
  shotImage: z.boolean().optional().describe('Also return that screenshot as an image (default false: saved only)'),
};

/**
 * Saves an evidence screenshot after an action. Best effort: a failed capture is
 * reported as text and never hides the action's own result.
 */
async function captureShot(path, withImage) {
  try {
    const { result } = await client.call('screenshot', { maxWidth: SHOT_WIDTH });
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, Buffer.from(result.pngBase64, 'base64'));
    const items = [{ type: 'text', text: `shot saved ${path}` }];
    if (withImage) items.unshift({ type: 'image', data: result.pngBase64, mimeType: 'image/png' });
    return items;
  } catch (e) {
    return [{ type: 'text', text: `shot failed: ${e.message ?? e}` }];
  }
}

/** Runs an action and, when `shot` is given, appends the evidence screenshot. */
async function withShot({ shot, shotImage }, action) {
  let out;
  try {
    out = await action();
  } catch (e) {
    out = fail(e);
  }
  if (shot) out = { ...out, content: [...out.content, ...(await captureShot(shot, shotImage))] };
  return out;
}

/**
 * Registers a tool that forwards to the app; `shape` is a zod raw shape.
 * With `shots: true` the tool also accepts `shot`/`shotImage` (evidence in the same call).
 */
function appTool(name, description, shape, method, { map, timeoutMs, shots = false } = {}) {
  const inputSchema = shots ? { ...shape, ...shotFields } : shape;
  server.registerTool(name, { description, inputSchema }, async (args) => {
    const { shot, shotImage, ...params } = args;
    const run = async () => {
      const body = await client.call(method ?? name, params, timeoutMs);
      return map ? map(body.result, params) : text(withExceptions(body.result, body));
    };
    return shots ? withShot({ shot, shotImage }, run) : run().catch(fail);
  });
}

function withExceptions(result, body) {
  return body.appErrors ? { result, appErrors: body.appErrors } : result;
}

// --- finder ------------------------------------------------------------

const finderFields = {
  text: z.string().optional().describe('Exact text of a Text / TextField'),
  textContaining: z.string().optional().describe('Substring of a Text / TextField'),
  key: z.string().optional().describe('Value of a ValueKey<String>, e.g. Key("login")'),
  type: z.string().optional().describe('Widget runtimeType, e.g. "FilledButton", "TextField", "ListView"'),
  tooltip: z.string().optional(),
  semanticsLabel: z.string().optional(),
  includeOffstage: z.boolean().optional().describe('Also match offstage widgets (default false)'),
  index: z.number().int().min(0).optional().describe('Which match to use when several (default 0)'),
};
const finder = z
  .object({
    ...finderFields,
    within: z
      .object(finderFields)
      .optional()
      .describe('Only match inside widgets matching this finder (same fields, no nesting)'),
  })
  .describe('Matches widgets; all given fields must match the same widget. Prefer key, then text.');

const settle = {
  settle: z.boolean().optional().describe('Wait for animations to finish after the action (default true)'),
  settleTimeoutMs: z.number().int().optional().describe('Max wait for settling (default 3000)'),
};

// --- app lifecycle tools -------------------------------------------------

server.registerTool(
  'app_launch',
  {
    description:
      'Build and start the Flutter app\'s MCP test entry point (e.g. integration_test/mcp_test.dart) on a device, ' +
      'then wait until it accepts commands. First build can take minutes.',
    inputSchema: {
      projectDir: z.string().describe('Absolute path of the Flutter project'),
      device: z.string().describe('Device id from `flutter devices` (e.g. emulator-5554, linux, <ios simulator id>)'),
      target: z.string().optional().describe('Entry point (default integration_test/mcp_test.dart)'),
      mode: z.enum(['run', 'test']).optional().describe('"run" = flutter run (default); "test" = flutter test (official integration_test flow; non-zero exit when an expect fails)'),
      port: z.number().int().min(1).max(65535).optional().describe('In-app server port (automatically selects a free local port when omitted)'),
      dartDefines: z.array(z.string()).optional().describe('Extra --dart-define values, KEY=VALUE'),
      extraArgs: z.array(z.string()).optional().describe('Extra flutter args, e.g. ["--flavor","dev"]'),
      adbForward: z.boolean().optional().describe('Run `adb forward` for the port (needed for Android devices/emulators)'),
      timeoutSec: z.number().int().optional().describe('Max wait for the first build (default 600)'),
    },
  },
  async ({ projectDir, device, target = 'integration_test/mcp_test.dart', mode = 'run', port, dartDefines, extraArgs, adbForward, timeoutSec = 600 }) => {
    try {
      const cmd = await launcher.start({ projectDir, device, target, mode, port, dartDefines, extraArgs, adbForward });
      client = new AppClient(`http://127.0.0.1:${launcher.port}`);
      const deadline = Date.now() + timeoutSec * 1000;
      while (Date.now() < deadline) {
        if (await client.health()) return text({ ready: true, command: cmd, url: client.baseUrl });
        if (launcher.exit) {
          return fail(new Error(`App process exited early (${JSON.stringify(launcher.exit)}). Last logs:\n${launcher.logs.slice(-25).join('\n')}`));
        }
        await new Promise((r) => setTimeout(r, 1000));
      }
      return fail(new Error(`Timed out after ${timeoutSec}s. Last logs:\n${launcher.logs.slice(-25).join('\n')}`));
    } catch (e) {
      return fail(e);
    }
  },
);

server.registerTool(
  'app_connect',
  {
    description: 'Point at an already-running MCP test build (started manually). For Android run `adb forward tcp:PORT tcp:PORT` first.',
    inputSchema: { port: z.number().int().optional(), host: z.string().optional().describe('default 127.0.0.1') },
  },
  async ({ port = DEFAULT_PORT, host = '127.0.0.1' }) => {
    client = new AppClient(`http://${host}:${port}`);
    return (await client.health()) ? text({ connected: true, url: client.baseUrl }) : fail(new Error(`Nothing answering at ${client.baseUrl}`));
  },
);

server.registerTool(
  'app_logs',
  { description: 'Last lines of the flutter process output (build errors, app prints).', inputSchema: { lines: z.number().int().optional() } },
  async ({ lines = 60 }) => text({ running: launcher.running, exit: launcher.exit, logs: launcher.logs.slice(-lines) }),
);

server.registerTool(
  'app_stop',
  {
    description:
      'End the session: reports expectation results, shuts the in-app server down and stops the flutter process. ' +
      'With flutter test mode, unacknowledged app errors (overflow, exceptions) fail the run unless ignoreErrors is true.',
    inputSchema: { ignoreErrors: z.boolean().optional().describe('Do not fail the run because of recorded app errors') },
  },
  async ({ ignoreErrors } = {}) => {
    let results;
    try {
      results = (await client.call('shutdown', { ignoreErrors: ignoreErrors === true }, 5000)).result;
    } catch {
      /* app may already be gone */
    }
    try {
      await launcher.stop();
    } catch (error) {
      return fail(error);
    }
    return text({ stopped: true, expectations: results });
  },
);

// --- inspection ------------------------------------------------------

appTool('app_status', 'Platform, logical screen size, pixel ratio and expectation counters.', {}, 'status');
appTool(
  'snapshot',
  'Text description of what is on screen: visible Text, inputs, buttons, switches… with key, text, bounds [left, top, width, height] and tappable. Call this first and after navigation.',
  { maxNodes: z.number().int().optional().describe('default 300') },
);
appTool('find', 'Count and describe widgets matching a finder.', { finder });
appTool('getText', 'Text content of the matched widget (Text / TextField), including descendants.', { finder });

server.registerTool(
  'screenshot',
  {
    description:
      'PNG screenshot of the app (debug/profile builds). Returns the image; with `path` it is also saved to that file (evidence).',
    inputSchema: {
      maxWidth: z.number().optional().describe('Max width in px (default 800)'),
      path: z.string().optional().describe('Absolute path of a .png file to save the screenshot to'),
    },
  },
  async ({ maxWidth, path }) => {
    try {
      const { result } = await client.call('screenshot', maxWidth === undefined ? {} : { maxWidth });
      const content = [{ type: 'image', data: result.pngBase64, mimeType: 'image/png' }];
      if (path) {
        mkdirSync(dirname(path), { recursive: true });
        writeFileSync(path, Buffer.from(result.pngBase64, 'base64'));
        content.push({ type: 'text', text: `saved ${path}` });
      }
      content.push({ type: 'text', text: `${result.width}x${result.height}` });
      return { content };
    } catch (e) {
      return fail(e);
    }
  },
);

// --- actions -----------------------------------------------------------

const shots = { shots: true };
appTool('tap', 'Tap the matched widget.', { finder, ...settle }, undefined, shots);
appTool('longPress', 'Long-press the matched widget.', { finder, ...settle }, undefined, shots);
appTool('doubleTap', 'Double-tap the matched widget.', { finder, ...settle }, undefined, shots);
appTool(
  'tapAt',
  'Tap at logical-pixel coordinates (use bounds from snapshot).',
  { x: z.number(), y: z.number(), ...settle },
  undefined,
  shots,
);
appTool(
  'enterText',
  'Type text into the matched TextField (replaces its content).',
  { finder, text: z.string(), submit: z.boolean().optional().describe('Send the "done" keyboard action afterwards'), ...settle },
  undefined,
  shots,
);
server.registerTool(
  'enterEnv',
  {
    description:
      'Type the value of a variable from the test env file into the matched TextField (replaces its content). ' +
      'Use for secrets (login, password): the value is never returned, only its length. Names come from `envKeys`.',
    inputSchema: {
      finder,
      name: z.string().describe('Variable name in the env file, e.g. E2E_LOGIN_PASSWORD'),
      submit: z.boolean().optional().describe('Send the "done" keyboard action afterwards'),
      ...settle,
      ...shotFields,
    },
  },
  async (args) => {
    const { name, shot, shotImage, ...params } = args;
    return withShot({ shot, shotImage }, async () => {
      const values = ENV_FILE ? loadEnvFile(ENV_FILE) : new Map();
      if (!values.has(name)) {
        const names = [...values.keys()].join(', ') || 'none';
        throw new Error(`Variable "${name}" is not defined in the env file (available names: ${names}).`);
      }
      const value = values.get(name);
      const body = await client.call('enterText', { ...params, text: value });
      return text({ typed: name, chars: [...value].length, settled: body.result.settled });
    });
  },
);

server.registerTool(
  'envKeys',
  { description: 'Names (never values) of the variables available to enterEnv.', inputSchema: {} },
  async () => {
    try {
      return text({ keys: ENV_FILE ? [...loadEnvFile(ENV_FILE).keys()] : [] });
    } catch (e) {
      return fail(e);
    }
  },
);

appTool(
  'drag',
  'Drag the matched widget by (dx, dy) logical px. Negative dy scrolls content up.',
  { finder, dx: z.number(), dy: z.number(), ...settle },
  undefined,
  shots,
);
appTool(
  'fling',
  'Fling the matched widget.',
  { finder, dx: z.number(), dy: z.number(), speed: z.number().optional(), ...settle },
  undefined,
  shots,
);
appTool(
  'scrollUntilVisible',
  'Scroll a scrollable until the target widget is built and visible.',
  {
    finder,
    scrollable: finder.optional().describe('Scrollable to drag (default: first Scrollable)'),
    delta: z.number().optional().describe('Vertical drag per step in px; negative reveals items below (default -200)'),
    dx: z.number().optional().describe('Horizontal drag per step'),
    maxScrolls: z.number().int().optional(),
    ...settle,
  },
  undefined,
  { timeoutMs: 120_000, shots: true },
);
appTool('pressBack', 'Simulate the system back button / pop route.', {}, undefined, shots);
appTool(
  'sendKey',
  'Send a keyboard key.',
  {
    key: z.enum(['enter', 'tab', 'escape', 'backspace', 'space', 'arrowUp', 'arrowDown', 'arrowLeft', 'arrowRight']),
    ...settle,
  },
  undefined,
  shots,
);
appTool('pump', 'Advance the frame clock by N ms.', { ms: z.number().int().optional() });
appTool('pumpAndSettle', 'Pump until no animation is running; errors on endless animations.', { timeoutMs: z.number().int().optional() });

// --- waiting / assertions -------------------------------------------------

appTool(
  'waitFor',
  'Wait until a widget appears (or disappears with absent=true).',
  { finder, absent: z.boolean().optional(), timeoutMs: z.number().int().optional().describe('default 10000') },
  undefined,
  { timeoutMs: 600_000, shots: true },
);
appTool(
  'expect',
  'Record an assertion (integration_test `expect`). Failures do not stop the session; they are listed by test_results and fail the test run on app_stop.',
  {
    finder,
    exists: z.boolean().optional().describe('Default: must exist'),
    count: z.number().int().optional().describe('Exact number of matches'),
    text: z.string().optional().describe('Text the widget must contain'),
  },
);
appTool(
  'app_errors',
  'List errors raised inside the app (RenderFlex overflow, build/layout/gesture exceptions) with count, command that triggered them and stack. Also returned as appErrors in any command response when new ones appear.',
  { clear: z.boolean().optional().describe('Acknowledge and clear them (so they do not fail the run)') },
  'errors',
);
appTool('test_results', 'Passed/failed expectation totals and failure messages.', {}, 'results');

await server.connect(new StdioServerTransport());

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    await launcher.stop();
    process.exit(0);
  });
}
