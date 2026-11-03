# TODO

Working notes for the ChessEx UI. See `README.md` for how to run it and
`ASSETS.md` for asset provenance.

## Done

- [x] Add the `/game` LiveView with a `Chess.Game` in progress.
- [x] Serve the game at `/` as the default route, keeping `/game` as an alias.
- [x] Render an 8×8 board with the `blue` lichess 2D texture and `gioco` pieces.
- [x] Render file labels below the board and rank labels on the left, flipping
      with orientation.
- [x] Two-click move selection: first click selects a piece, second click on a
      highlighted destination applies the move.
- [x] Highlight the selected square, legal destinations, capture targets and the
      last move.
- [x] Send a `square_click` LiveView event for every square.
- [x] Derive legal targets from `Chess.Rules.legal_moves/1` and guard the
      applied move with `Chess.Rules.legal_move?/2`.
- [x] Let the engine answer with `Chess.Engine.play/1`; the player can choose
      White or Black via **Switch sides**.
- [x] Add **New game**, **Switch sides** and **Resign** controls.
- [x] Add a status panel using `Chess.Narrator` and a PGN-style move list.
- [x] Fit the board and panels in one viewport without page scrolling; panels
      scroll internally.
- [x] Remove the application header/theme toggle from `/game` via the `bare`
      layout.
- [x] Add LiveView tests and board/asset unit tests.
- [x] Document assets and licenses in `ASSETS.md`.
- [x] Make engine strength configurable in `config.exs`: 4-ply `Chess.Search`
      with the opening book, through `ChessUI.Engine`.
- [x] Run engine moves asynchronously with a visible “thinking” state in the
      turn indicator; the board is locked meanwhile.
- [x] Cancel and ignore stale engine work after a new game, resign or side
      switch.
- [x] Make the title open an About dialog with placeholder copy, links and the
      runtime details from `ChessUI.SystemInfo`.
- [x] Save completed games automatically as PGN files with timestamps, player
      colors, result, termination reason, engine options and a game id.
- [x] Add a chronological `/history` hall of fame with win/draw statistics.
- [x] Add a read-only `/history/:id` replay with move navigation.
- [x] Add PGN download from the history, replay and game pages.
- [x] Add an anonymous, textual REST API for machines and AIs: create a game,
      read its FEN, play a SAN/UCI move and let the engine answer.
- [x] Rate limit API game creation, moves and reads; cap games, idle time and
      concurrent engine searches.
- [x] Archive finished API games in the same PGN history, labelled `API`.

## Next

### Gameplay

- [ ] Replace auto-queen with a promotion picker (queen, rook, bishop, knight).
- [x] Highlight the king in check with a red glow on the board.
- [ ] Highlight the checkmating move/target.
- [ ] Show captured pieces and material balance.
- [ ] Add drag-and-drop as an alternative to two clicks.
- [ ] Add keyboard navigation and activation for board squares.
- [ ] Consider a “flip board only” action separate from switching sides.

### Engine

- [ ] Expose engine strength in the UI (random, 1-ply, search depth, book on/off)
      instead of only in `config.exs`.
- [ ] Decide whether to keep the in-process engine or drive the `chess_ex`
      UCI executable.
- [ ] Add an option to play both sides locally (engine disabled).

### Game records and lifecycle

- [ ] Persist an in-progress game across refreshes/reconnects.
- [x] Persist and list finished games.
- [ ] Import PGN/FEN; export FEN and add a copy-PGN action.
- [x] Browse backward/forward through the move history of a completed game.
- [ ] Add deletion, retention and pagination for a large game archive.
- [ ] Add an index/cache if reading all PGN files becomes slow.
- [ ] Refresh the history page live when another tab finishes a game.
- [ ] Add a clock/timer.
- [ ] Consider draw offers, rematches and result handling beyond resignation.

### UI and assets

- [ ] Add a board/piece theme picker and more lichess sets selected through
      `ChessUIWeb.ChessAssets`.
- [ ] Verify light, dark and system themes consistently, including the board
      coordinates and panel contrast.
- [ ] Audit asset licenses if the project is ever used commercially; the Gioco
      pieces are CC BY-NC-SA 4.0.
- [ ] Re-check the one-page fit on very short and very narrow viewports.
- [ ] Add subtle move animations and sound effects if they remain optional.

### Tests and engineering

- [ ] Add tests for promotion, castling, en passant and checks.
- [ ] Add a test that plays a complete game to checkmate.
- [ ] Add a test for playing as Black after the engine opens.
- [ ] Add CI that runs `mix precommit` and `mix assets.build`.

### REST API

- [ ] Decide whether API games should survive a restart; today they are
      in-memory only, like LiveView games.
- [ ] Add an idempotency key to game creation so a retried `POST /api/games`
      does not create a second game.
- [ ] Add a `DELETE /api/games/:id` abandon operation that frees a slot without
      writing a record.
- [ ] Add CORS only if browser-based clients need to call the API.
- [ ] Add a small script that plays an API game end to end for smoke testing.

## First-pass constraints

These are deliberate for now, not bugs:

- the game page is one viewport with no page scrolling; history pages scroll
- no clock/timer or settings
- in-progress game state in the LiveView only; completed games are PGN files
- history reads the games directory on demand, without an index
- resignation records the game; starting over or switching sides does not
- engine strength fixed in `config.exs` (4-ply search + opening book)
- auto-queen promotion
- `blue` board + `gioco` pieces, with `ChessAssets` as the swap point
