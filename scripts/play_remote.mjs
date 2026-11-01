#!/usr/bin/env node
//
// Play a game against a running ChessEx UI instance, as a black box.
//
// The script drives a real browser through the public page only: it clicks
// `#square-*` buttons, reads the state attributes the board publishes and never
// touches a private endpoint, a socket payload or the filesystem of the server.
//
//   node scripts/play_remote.mjs                  # against http://localhost:4000
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
// The bot is a demonstration opponent, not a chess engine: it sees the legal
// destinations the UI highlights, prefers captures, and otherwise develops. It
// exists to prove the page is drivable, and it will lose.

import { createRequire } from "node:module";
import process from "node:process";

const require = createRequire(import.meta.url);

const SQUARE_ID_PREFIX = "square-";
const PIECE_VALUE = { pawn: 1, knight: 3, bishop: 3, rook: 5, queen: 9, king: 0 };
const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1", "0.0.0.0", "[::1]"]);

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

function usage() {
  return `Usage: node scripts/play_remote.mjs [options]

  --url <url>          page to drive (default: $BASE_URL or http://localhost:4000)
  --max-moves <n>      resign after this many own moves (default: 200)
  --timeout <ms>       per-wait timeout (default: 20000)
  --colour <c>         play white or black (default: white)
  --no-archive         resign nothing: close the page instead of finishing
                       (only useful to check that a game starts)
  --headed             show the browser window
  -h, --help           this message`;
}

function parseArgs(argv) {
  const opts = {
    url: process.env.BASE_URL || "http://localhost:4000/",
    maxMoves: 200,
    timeout: 20_000,
    colour: "white",
    headed: false,
    archive: true,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (value === undefined) throw new Error(`${arg} needs a value`);
      return value;
    };

    switch (arg) {
      case "--url":
        opts.url = next();
        break;
      case "--max-moves":
        opts.maxMoves = Number(next());
        break;
      case "--timeout":
        opts.timeout = Number(next());
        break;
      case "--colour":
      case "--color":
        opts.colour = next().toLowerCase();
        break;
      case "--no-archive":
        opts.archive = false;
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
    { p: "pawn", n: "knight", b: "bishop", r: "rook", q: "queen", k: "king" }[char] ??
    "unknown"
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

function readMoves(page) {
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
async function selectSquare(page, square, opts) {
  await page.click(`#${SQUARE_ID_PREFIX}${square}`, { timeout: opts.timeout });
  await page.waitForFunction(
    (target) => document.querySelector(`#square-${target}`)?.dataset.selected === "true",
    square,
    { timeout: opts.timeout }
  );
}

async function waitForPly(page, ply, opts) {
  await page.waitForFunction(
    (expected) => Number(document.querySelector("#board")?.dataset.ply) >= expected,
    ply,
    { timeout: opts.timeout }
  );
}

// ---------------------------------------------------------------------------
// Move selection
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

  for (const [from, piece] of ours) {
    if (state.selected !== from) {
      await selectSquare(page, from, opts);
      state.selected = from;
    }

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
// Game
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
    if (before.selected !== move.from) await selectSquare(page, move.from, opts);
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

  return { final, moves: await readMoves(page) };
}

// ---------------------------------------------------------------------------

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const target = new globalThis.URL(opts.url);
  const isLocal = LOCAL_HOSTS.has(target.hostname) || target.hostname.endsWith(".localhost");

  if (!isLocal && process.env.ALLOW_REMOTE !== "1") {
    console.error(
      `refusing to drive ${target.origin}: a finished game is archived publicly.\n` +
        "Set ALLOW_REMOTE=1 if that is really what you want."
    );
    process.exit(2);
  }

  const chromium = await loadPlaywright();
  const browser = await chromium.launch({
    channel: process.env.PLAYWRIGHT_CHANNEL || "chrome",
    headless: !opts.headed,
  });

  const problems = [];
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  page.on("pageerror", (error) => problems.push(`page error: ${error.message}`));
  page.on("console", (message) => {
    if (message.type() === "error") problems.push(`console error: ${message.text()}`);
  });

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

    if (problems.length > 0) {
      console.log("\npage problems:");
      for (const problem of problems) console.log(`  - ${problem}`);
      process.exitCode = 1;
    }

    process.exitCode = process.exitCode ?? 0;
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(`\nfailed: ${error.message}`);
  process.exitCode = 1;
});
