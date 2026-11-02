#!/usr/bin/env node
//
// Play a game against a running ChessEx UI instance, as a black box.
//
// The script drives a real browser through the public page only: it clicks
// `#square-*` buttons, reads the state attributes the board publishes and never
// touches a private endpoint, a socket payload or the filesystem of the server.
//
//   node scripts/play_remote.mjs                  # autonomous demo game
//   BASE_URL=http://localhost:4001 node scripts/play_remote.mjs
//   ALLOW_REMOTE=1 node scripts/play_remote.mjs --url https://chess.stfx.eu
//
// Requirements: Node 20+, Google Chrome installed (no browser download), and
// the `playwright-core` package from `scripts/package.json`:
//
//   npm --prefix scripts install
//
// A finished game is archived permanently in /history, so any host other than
// localhost is refused unless ALLOW_REMOTE=1 is set explicitly.
//
// ## Interactive session
//
// The autonomous game below plays a heuristic demo. To play move by move from
// outside the process, start a session and talk to it:
//
//   node scripts/play_remote.mjs --serve          # background; prints the FEN
//   node scripts/play_remote.mjs --state          # position + legal moves
//   node scripts/play_remote.mjs --step e2e4      # play it, wait for the reply
//   node scripts/play_remote.mjs --close          # end it, or --close --resign
//
// The session holds one browser tab, because the game lives in that LiveView
// process. It listens on 127.0.0.1 only, on a random port, and requires the
// token it writes to tmp/play_session.json.

import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { createServer } from "node:http";
import { randomBytes } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const require = createRequire(import.meta.url);

const SQUARE_ID_PREFIX = "square-";
const PIECE_VALUE = { pawn: 1, knight: 3, bishop: 3, rook: 5, queen: 9, king: 0 };
const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1", "0.0.0.0", "[::1]"]);
const SESSION_FILE = fileURLToPath(new URL("../tmp/play_session.json", import.meta.url));

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

function usage() {
  return `Usage: node scripts/play_remote.mjs [mode] [options]

Modes (default: play an autonomous demo game):
  --serve              open a session and keep the browser alive in the
                       background, listening on 127.0.0.1
  --state              print the current position and every legal move
  --step <move>        play one move (e2e4) and wait for the engine's reply
  --close              end the session (add --resign to resign first)

Options:
  --url <url>          page to drive (default: $BASE_URL or http://localhost:4000)
  --colour <c>         play white or black (default: white)
  --max-moves <n>      autonomous mode: resign after this many own moves (200)
  --timeout <ms>       per-wait timeout (default: 20000)
  --ttl <minutes>      session mode: close after this long idle (default: 60)
  --no-legal           --state: skip the legal move scan (faster)
  --no-archive         autonomous mode: stop without a result, archive nothing
  --headed             show the browser window
  -h, --help           this message`;
}

function parseArgs(argv) {
  const opts = {
    mode: "play",
    url: process.env.BASE_URL || "http://localhost:4000/",
    maxMoves: 200,
    timeout: 20_000,
    ttlMinutes: 60,
    colour: "white",
    headed: false,
    archive: true,
    legal: true,
    resign: false,
    move: null,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (value === undefined) throw new Error(`${arg} needs a value`);
      return value;
    };

    switch (arg) {
      case "--serve":
        opts.mode = "serve";
        break;
      case "--state":
        opts.mode = "state";
        break;
      case "--step":
        opts.mode = "step";
        opts.move = next();
        break;
      case "--close":
        opts.mode = "close";
        break;
      case "--url":
        opts.url = next();
        break;
      case "--max-moves":
        opts.maxMoves = Number(next());
        break;
      case "--timeout":
        opts.timeout = Number(next());
        break;
      case "--ttl":
        opts.ttlMinutes = Number(next());
        break;
      case "--colour":
      case "--color":
        opts.colour = next().toLowerCase();
        break;
      case "--no-legal":
        opts.legal = false;
        break;
      case "--no-archive":
        opts.archive = false;
        break;
      case "--resign":
        opts.resign = true;
        break;
      case "--headed":
        opts.headed = true;
        break;
      case "-h":
      case "--help":
        console.log(usage());
        process.exit(0);
        break;
      default:
        throw new Error(`unknown option ${arg}\n\n${usage()}`);
    }
  }

  if (!["white", "black"].includes(opts.colour)) {
    throw new Error(`--colour must be white or black, got ${opts.colour}`);
  }

  return opts;
}

function assertLocal(opts) {
  const target = new globalThis.URL(opts.url);
  const isLocal = LOCAL_HOSTS.has(target.hostname) || target.hostname.endsWith(".localhost");

  if (!isLocal && process.env.ALLOW_REMOTE !== "1") {
    throw new Error(
      `refusing to drive ${target.origin}: a finished game is archived publicly.\n` +
        "Set ALLOW_REMOTE=1 if that is really what you want."
    );
  }

  return target;
}

// ---------------------------------------------------------------------------
// Playwright resolution
// ---------------------------------------------------------------------------

async function loadPlaywright() {
  const candidates = [process.env.PLAYWRIGHT_MODULE, "playwright", "playwright-core"].filter(
    Boolean
  );

  for (const candidate of candidates) {
    try {
      const mod = await import(new URL(`file://${require.resolve(candidate)}`).href);
      const chromium = mod.chromium ?? mod.default?.chromium;
      if (chromium) return chromium;
    } catch {
      // try the next candidate
    }
  }

  throw new Error(
    "could not load Playwright. Run `npm --prefix scripts install` first, " +
      "or set PLAYWRIGHT_MODULE to an installed playwright/playwright-core path."
  );
}

async function openBrowser(opts) {
  const chromium = await loadPlaywright();
  const browser = await chromium.launch({
    channel: process.env.PLAYWRIGHT_CHANNEL || "chrome",
    headless: !opts.headed,
  });

  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const problems = [];
  page.on("pageerror", (error) => problems.push(`page error: ${error.message}`));
  page.on("console", (message) => {
    if (message.type() === "error") problems.push(`console error: ${message.text()}`);
  });

  return { browser, page, problems };
}

// ---------------------------------------------------------------------------
// Page state
// ---------------------------------------------------------------------------

function parseFen(fen) {
  const [placement, side] = fen.split(" ");
  const pieces = new Map();

  placement.split("/").forEach((row, index) => {
    let file = 0;
    for (const char of row) {
      if (char >= "1" && char <= "8") {
        file += Number(char);
        continue;
      }
      const square = "abcdefgh"[file] + (8 - index);
      pieces.set(square, {
        color: char === char.toUpperCase() ? "white" : "black",
        type: pieceName(char.toLowerCase()),
      });
      file++;
    }
  });

  return { pieces, sideToMove: side === "w" ? "white" : "black" };
}

function pieceName(char) {
  return (
    { p: "pawn", n: "knight", b: "bishop", r: "rook", q: "queen", k: "king" }[char] ?? "unknown"
  );
}

function readState(page) {
  return page.evaluate(() => {
    const board = document.querySelector("#board");
    if (!board) return null;

    return {
      fen: board.dataset.fen,
      sideToMove: board.dataset.sideToMove,
      ply: Number(board.dataset.ply),
      busy: board.dataset.busy === "true",
      orientation: board.dataset.orientation,
      thinking: document.querySelector("#turn-indicator")?.dataset.thinking === "true",
      gameOver: document.querySelector("#status")?.dataset.gameOver === "true",
      result: document.querySelector("#result")?.dataset.result,
      status: document.querySelector("#status")?.textContent.trim(),
      gameId: document.querySelector("#recorded-game")?.dataset.gameId ?? null,
      selected: document.querySelector('[data-selected="true"]')?.id.slice(7) ?? null,
    };
  });
}

function readTargets(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll('[data-target="true"]')].map((el) => el.id.slice(7))
  );
}

function readSans(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll("#moves [data-ply]")].map((el) => el.textContent.trim())
  );
}

function readMoveRows(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll("#moves tr[id^='move-']")].map((row) =>
      row.innerText.replace(/\s+/g, " ").trim()
    )
  );
}

// ---------------------------------------------------------------------------
// Waiting
// ---------------------------------------------------------------------------

async function waitForOurTurn(page, opts) {
  await page.waitForFunction(
    () => {
      const board = document.querySelector("#board");
      const status = document.querySelector("#status");
      return board?.dataset.busy === "false" && status?.dataset.gameOver === "false";
    },
    null,
    { timeout: opts.timeout }
  );
}

// Confirms the round trip: `select/2` always marks the clicked square, even when
// the piece has no legal destination, so this is the settle signal.
async function selectPiece(page, square, opts, currentSelected = null) {
  if (currentSelected === square) return true;

  try {
    await page.click(`#${SQUARE_ID_PREFIX}${square}`, { timeout: opts.timeout });
    await page.waitForFunction(
      (target) => document.querySelector(`#square-${target}`)?.dataset.selected === "true",
      square,
      { timeout: opts.timeout }
    );
    return true;
  } catch {
    return false;
  }
}

async function waitForPly(page, ply, opts) {
  await page.waitForFunction(
    (expected) => Number(document.querySelector("#board")?.dataset.ply) >= expected,
    ply,
    { timeout: opts.timeout }
  );
}

// ---------------------------------------------------------------------------
// Legal moves
// ---------------------------------------------------------------------------

// Ask the page which destinations it highlights for each of our pieces. The UI
// already derives this from Chess.Rules.legal_moves/1, so the driver never
// duplicates move generation.
async function legalMoves(page, state, colour, opts) {
  const { pieces } = parseFen(state.fen);
  const moves = {};
  let selected = state.selected;

  for (const [from, piece] of pieces) {
    if (piece.color !== colour) continue;
    if (!(await selectPiece(page, from, opts, selected))) continue;
    selected = from;
    moves[from] = await readTargets(page);
  }

  return moves;
}

function flatten(moves) {
  return Object.entries(moves)
    .flatMap(([from, tos]) => tos.map((to) => `${from}${to}`))
    .sort();
}

function normaliseMove(raw) {
  const cleaned = String(raw)
    .toLowerCase()
    .replace(/[^a-h1-8]/g, "");

  if (!/^[a-h][1-8][a-h][1-8]$/.test(cleaned)) {
    throw new Error(`expected a move like e2e4 or e2-e4, got ${JSON.stringify(raw)}`);
  }

  return { from: cleaned.slice(0, 2), to: cleaned.slice(2, 4) };
}

// ---------------------------------------------------------------------------
// Snapshots
// ---------------------------------------------------------------------------

async function snapshot(page, opts, { withLegal = true } = {}) {
  const state = await readState(page);
  if (!state) throw new Error("the page has no #board");

  const snap = {
    fen: state.fen,
    sideToMove: state.sideToMove,
    ply: state.ply,
    busy: state.busy,
    thinking: state.thinking,
    gameOver: state.gameOver,
    result: state.result,
    status: state.status,
    gameId: state.gameId,
    orientation: state.orientation,
    sans: await readSans(page),
  };

  if (withLegal && !state.gameOver) {
    const moves = await legalMoves(page, state, opts.colour, opts);
    snap.legal = moves;
    snap.legalCount = flatten(moves).length;
  }

  return snap;
}

function printSnapshot(snap, { legal = true } = {}) {
  console.log(`fen:    ${snap.fen}`);
  console.log(`side:   ${snap.sideToMove}   ply: ${snap.ply}   result: ${snap.result}`);

  if (snap.status) console.log(`status: ${snap.status}`);
  if (snap.sans?.length) console.log(`moves:  ${snap.sans.join(" ")}`);

  if (legal && snap.legal) {
    const groups = Object.entries(snap.legal).filter(([, tos]) => tos.length > 0);
    const text = groups.map(([from, tos]) => `${from}:${tos.join(",")}`).join("  ");
    console.log(`legal:  ${text || "(none)"}   (${snap.legalCount ?? 0} moves)`);
  }

  if (snap.gameId) console.log(`archived: ${snap.gameId}`);
}

// ---------------------------------------------------------------------------
// Move selection (autonomous demo)
// ---------------------------------------------------------------------------

function centreScore(square) {
  const fileDistance = Math.abs("abcdefgh".indexOf(square[0]) - 3.5);
  const rankDistance = Math.abs(Number(square[1]) - 4.5);
  return -(fileDistance + rankDistance);
}

function scoreMove({ piece, from, to, capture, ply }) {
  let score = centreScore(to) * 2;

  if (capture) score += 1000 + PIECE_VALUE[capture.type] * 50;
  if (piece.type === "knight" || piece.type === "bishop") score += 6;
  // Keep the queen home for the first few moves; it only ever gets lost.
  if (piece.type === "queen" && ply < 12) score -= 40;
  // Do not shuffle the rooks into the open before castling.
  if (piece.type === "rook" && from[1] === "1") score -= 25;
  if (to[1] === "1" || to[1] === "8") score -= 10;
  if (to === from) score -= 1000;

  return score;
}

async function chooseMove(page, state, colour, opts) {
  const { pieces } = parseFen(state.fen);
  const ours = [...pieces].filter(([, piece]) => piece.color === colour);
  let best = null;
  let selected = state.selected;

  for (const [from, piece] of ours) {
    if (!(await selectPiece(page, from, opts, selected))) continue;
    selected = from;

    for (const to of await readTargets(page)) {
      const capture = pieces.get(to) ?? null;
      if (capture && capture.color === colour) continue;

      const score = scoreMove({ piece, from, to, capture, ply: state.ply });
      if (!best || score > best.score) best = { from, to, score, capture, piece };
    }
  }

  return best;
}

// ---------------------------------------------------------------------------
// One interactive move
// ---------------------------------------------------------------------------

async function playStep(page, opts, rawMove) {
  const { from, to } = normaliseMove(rawMove);

  const before = await readState(page);
  if (!before) throw new Error("the page has no #board");
  if (before.gameOver) throw new Error(`the game is over (${before.result}): ${before.status}`);

  await waitForOurTurn(page, opts);

  const turn = await readState(page);
  if (turn.sideToMove !== opts.colour) {
    throw new Error(`it is ${turn.sideToMove} to move, not ${opts.colour}`);
  }

  const moves = await legalMoves(page, turn, opts.colour, opts);
  const selected = await readState(page);

  if (!(moves[from] ?? []).includes(to)) {
    return {
      applied: false,
      error: `${from}${to} is not a legal move`,
      ...(await snapshot(page, opts, { withLegal: false })),
      legal: moves,
      legalCount: flatten(moves).length,
    };
  }

  const sansBefore = await readSans(page);

  if (!(await selectPiece(page, from, opts, selected.selected))) {
    throw new Error(`could not select ${from}`);
  }

  await page.click(`#${SQUARE_ID_PREFIX}${to}`, { timeout: opts.timeout });
  await waitForPly(page, turn.ply + 1, opts);

  const sansAfterMine = await readSans(page);
  const mine = sansAfterMine.slice(sansBefore.length)[0] ?? null;

  let engineSan = null;
  try {
    await waitForPly(page, turn.ply + 2, opts);
    const sansAfterEngine = await readSans(page);
    engineSan = sansAfterEngine.slice(sansBefore.length)[1] ?? null;
  } catch {
    // The engine's reply may be the last move of the game, or the game may be
    // over already; the snapshot below reports what actually happened.
  }

  const after = await snapshot(page, opts, { withLegal: true });

  return { applied: true, from, to, mine, engineSan, ...after };
}

// ---------------------------------------------------------------------------
// Session server
// ---------------------------------------------------------------------------

async function serve(opts) {
  const target = assertLocal(opts);
  const { browser, page, problems } = await openBrowser(opts);
  const token = randomBytes(16).toString("hex");

  const shutdown = async (exitCode = 0) => {
    await rm(SESSION_FILE, { force: true });
    await browser.close().catch(() => {});
    process.exit(exitCode);
  };

  process.on("SIGINT", () => void shutdown(130));
  process.on("SIGTERM", () => void shutdown(143));

  await page.goto(target.href, { waitUntil: "domcontentloaded", timeout: opts.timeout });
  await page.waitForSelector("#board", { timeout: opts.timeout });

  if (opts.colour !== (await readState(page)).orientation) {
    await page.click("#switch-sides", { timeout: opts.timeout });
    await waitForPly(page, 1, opts).catch(() => {});
  }

  // Requests are handled one at a time; a move and a read must not interleave.
  let queue = Promise.resolve();
  const serialise = (task) => {
    const run = queue.then(task, task);
    queue = run.catch(() => {});
    return run;
  };

  const server = createServer((req, res) => {
    const reply = (status, body) => {
      res.writeHead(status, { "content-type": "application/json" });
      res.end(JSON.stringify(body));
    };

    if (req.headers["x-session-token"] !== token) {
      reply(401, { error: "unauthorised" });
      req.resume();
      return;
    }

    const url = new globalThis.URL(req.url, "http://127.0.0.1");

    if (req.method === "GET" && url.pathname === "/state") {
      req.resume();
      serialise(() => snapshot(page, opts, { withLegal: opts.legal }))
        .then((snap) => reply(200, { ok: true, problems, ...snap }))
        .catch((error) => reply(500, { ok: false, error: error.message }));
      return;
    }

    if (req.method === "POST" && (url.pathname === "/step" || url.pathname === "/close")) {
      let raw = "";
      req.on("data", (chunk) => (raw += chunk));
      req.on("end", () => {
        let body = {};
        try {
          body = raw ? JSON.parse(raw) : {};
        } catch {
          reply(400, { ok: false, error: "body must be JSON" });
          return;
        }

        if (url.pathname === "/step") {
          serialise(async () => {
            try {
              if (body.move) {
                return reply(200, { problems, ...(await playStep(page, opts, body.move)) });
              }
              return reply(200, { ok: true, problems, ...(await snapshot(page, opts)) });
            } catch (error) {
              return reply(400, { ok: false, error: error.message });
            }
          });
          return;
        }

        serialise(async () => {
          try {
            if (body.resign !== false) await resignIfPlaying(page, opts);
            const final = await snapshot(page, opts, { withLegal: false });
            reply(200, { ok: true, problems, ...final, moves: await readMoveRows(page) });
            setTimeout(() => void shutdown(0), 50);
          } catch (error) {
            reply(500, { ok: false, error: error.message });
          }
        });
      });
      return;
    }

    reply(404, { error: "not found" });
    req.resume();
  });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();

  await mkdir(path.dirname(SESSION_FILE), { recursive: true });
  await writeFile(
    SESSION_FILE,
    JSON.stringify({ port, token, url: target.href, pid: process.pid, startedAt: new Date().toISOString() }, null, 2),
    { mode: 0o600 }
  );

  console.log(`session: http://127.0.0.1:${port}  (state file: ${path.relative(process.cwd(), SESSION_FILE)})`);
  console.log(`playing ${opts.colour} on ${target.origin}\n`);
  printSnapshot(await snapshot(page, opts, { withLegal: true }));

  const ttl = opts.ttlMinutes * 60_000;
  if (ttl > 0) {
    const timer = setTimeout(() => {
      console.log(`\nsession idle for ${opts.ttlMinutes} minutes, closing.`);
      void shutdown(0);
    }, ttl);
    timer.unref?.();
  }
}

async function resignIfPlaying(page, opts) {
  const state = await readState(page);
  if (!state || state.gameOver) return;

  await page.click("#resign", { timeout: opts.timeout });
  await page.waitForFunction(
    () => document.querySelector("#status")?.dataset.gameOver === "true",
    null,
    { timeout: opts.timeout }
  );
}

// ---------------------------------------------------------------------------
// Session client
// ---------------------------------------------------------------------------

async function readSession() {
  try {
    return JSON.parse(await readFile(SESSION_FILE, "utf8"));
  } catch {
    throw new Error("no session found. Start one with `node scripts/play_remote.mjs --serve`.");
  }
}

async function sessionRequest(session, method, pathname, body) {
  const response = await fetch(`http://127.0.0.1:${session.port}${pathname}`, {
    method,
    headers: {
      "x-session-token": session.token,
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(180_000),
  });

  const payload = await response.json().catch(() => ({ ok: false, error: "invalid response" }));
  if (!response.ok || payload.ok === false) {
    throw new Error(payload.error ?? `session returned ${response.status}`);
  }

  return payload;
}

async function client(opts) {
  const session = await readSession();

  if (opts.mode === "state") {
    const snap = await sessionRequest(session, "GET", "/state");
    printSnapshot(snap, { legal: opts.legal });
    reportProblems(snap.problems);
    return;
  }

  if (opts.mode === "step") {
    const result = await sessionRequest(session, "POST", "/step", { move: opts.move });

    if (result.applied === false) {
      console.log(`illegal: ${result.error}`);
      printSnapshot(result, { legal: true });
      process.exitCode = 1;
      return;
    }

    console.log(`you:    ${result.mine ?? `${result.from}${result.to}`}`);
    console.log(`engine: ${result.engineSan ?? "(game over)"}`);
    console.log("");
    printSnapshot(result, { legal: true });
    reportProblems(result.problems);
    return;
  }

  // close
  const result = await sessionRequest(session, "POST", "/close", { resign: opts.resign });
  console.log(`result: ${result.result}   ${result.status}`);
  console.log(`plies:  ${result.ply}`);
  if (result.gameId) {
    const base = new URL(session.url).origin;
    console.log(`archived: ${result.gameId}`);
    console.log(`replay:   ${base}/history/${result.gameId}`);
    console.log(`pgn:      ${base}/history/${result.gameId}/download`);
  } else {
    console.log("not archived (the game had no result)");
  }
  reportProblems(result.problems);
}

function reportProblems(problems) {
  if (!problems || problems.length === 0) return;

  console.log("\npage problems:");
  for (const problem of problems) console.log(`  - ${problem}`);
  process.exitCode = 1;
}

// ---------------------------------------------------------------------------
// Game (autonomous demo)
// ---------------------------------------------------------------------------

async function play(page, opts) {
  const start = await readState(page);
  if (!start) throw new Error("the page has no #board");

  if (!/^[rnbqkpRNBQKP1-8/]+ [wb] /.test(start.fen ?? "")) {
    throw new Error(`#board does not publish a FEN (got ${JSON.stringify(start.fen)})`);
  }

  console.log(`board: ${start.orientation} at the bottom, ${start.fen}`);
  console.log(`${start.status} — playing ${opts.colour}\n`);

  let ownMoves = 0;
  let resignReason = null;

  for (;;) {
    const state = await readState(page);
    if (state.result !== "*") break;
    if (ownMoves >= opts.maxMoves) {
      resignReason = `reached ${opts.maxMoves} moves`;
      break;
    }

    try {
      await waitForOurTurn(page, opts);
    } catch {
      const stalled = await readState(page);
      if (stalled.result !== "*") break;
      resignReason = "the board never became ready";
      break;
    }

    const turn = await readState(page);
    if (turn.result !== "*") break;

    if (turn.sideToMove !== opts.colour) {
      resignReason = `expected ${opts.colour} to move, board says ${turn.sideToMove}`;
      break;
    }

    let move;
    try {
      move = await chooseMove(page, turn, opts.colour, opts);
    } catch (error) {
      resignReason = `could not choose a move: ${error.message}`;
      break;
    }

    if (!move) {
      // No legal destination anywhere. That is a real terminal position, not a
      // script failure, so let the board settle instead of resigning.
      resignReason = "no legal move found";
      break;
    }

    const before = await readState(page);
    if (!(await selectPiece(page, move.from, opts, before.selected))) {
      resignReason = `could not select ${move.from}`;
      break;
    }

    await page.click(`#${SQUARE_ID_PREFIX}${move.to}`, { timeout: opts.timeout });
    ownMoves++;

    try {
      await waitForPly(page, before.ply + 1, opts);
    } catch {
      resignReason = `the move ${move.from}${move.to} never landed`;
      break;
    }

    const afterOwnMove = await readState(page);
    if (afterOwnMove.result !== "*") break;

    // The engine answers in a background task; wait for its ply, or for the
    // game to end if its move is the last one.
    try {
      await waitForPly(page, before.ply + 2, opts);
    } catch {
      const stalled = await readState(page);
      if (stalled.result === "*") {
        resignReason = "the engine never moved";
        break;
      }
    }

    const reply = await readState(page);
    const san = await page.evaluate(
      () => [...document.querySelectorAll("#moves [data-ply]")].pop()?.textContent.trim() ?? ""
    );
    console.log(
      `#${ownMoves} ${move.from}-${move.to}${move.capture ? `x${move.capture.type}` : ""}` +
        `${san ? `  (last: ${san})` : ""}  ${reply.status ?? ""}`
    );
  }

  let final = await readState(page);

  if (final.result === "*") {
    const reason = resignReason ?? "stopped";
    if (opts.archive) {
      console.log(`\nresigning: ${reason}`);
      await page.click("#resign", { timeout: opts.timeout });
      await page.waitForFunction(
        () => document.querySelector("#status")?.dataset.gameOver === "true",
        null,
        { timeout: opts.timeout }
      );
    } else {
      console.log(`\nstopping without a result, nothing will be archived: ${reason}`);
    }
    final = await readState(page);
  }

  return { final, moves: await readMoveRows(page) };
}

async function autonomous(opts) {
  const target = assertLocal(opts);
  const { browser, page, problems } = await openBrowser(opts);

  try {
    await page.goto(target.href, { waitUntil: "domcontentloaded", timeout: opts.timeout });
    await page.waitForSelector("#board", { timeout: opts.timeout });

    if (opts.colour !== "white") {
      // Switching sides starts a fresh game and hands the first move to the
      // engine, which then plays as white.
      await page.click("#switch-sides", { timeout: opts.timeout });
      await waitForPly(page, 1, opts).catch(() => {});
    }

    const { final, moves } = await play(page, opts);

    console.log(`\nresult: ${final.result}  —  ${final.status}`);
    console.log(`plies: ${final.ply}`);
    console.log(`moves: ${moves.join(" ")}`);

    if (final.gameId) {
      console.log(`archived: ${final.gameId}`);
      console.log(`replay:   ${target.origin}/history/${final.gameId}`);
      console.log(`pgn:      ${target.origin}/history/${final.gameId}/download`);
    } else if (opts.archive) {
      console.log("not archived (no #recorded-game element)");
      problems.push("a result was reached but no game record was published");
    }

    reportProblems(problems);
  } finally {
    await browser.close();
  }
}

// ---------------------------------------------------------------------------

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  switch (opts.mode) {
    case "serve":
      await serve(opts);
      break;
    case "state":
    case "step":
    case "close":
      await client(opts);
      break;
    default:
      await autonomous(opts);
  }
}

main().catch((error) => {
  console.error(`\nfailed: ${error.message}`);
  process.exitCode = 1;
});
