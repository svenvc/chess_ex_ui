# TODO

Working notes for the ChessEx UI. See `README.md` for how to run it and
`ASSETS.md` for asset provenance.

## Done

- [x] Add the `/game` LiveView with a `Chess.Game` in progress.
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

## Next

### Gameplay

- [ ] Replace auto-queen with a promotion picker (queen, rook, bishop, knight).
- [ ] Highlight the king in check and the checkmating move/target.
- [ ] Show captured pieces and material balance.
- [ ] Add drag-and-drop as an alternative to two clicks.
- [ ] Add keyboard navigation and activation for board squares.
- [ ] Consider a “flip board only” action separate from switching sides.

### Engine

- [ ] Make engine strength configurable: random, 1-ply best, search depth and
      opening book.
- [ ] Run engine moves asynchronously with a visible “thinking” state.
- [ ] Ignore or cancel stale engine work after a new game, resign or side
      switch.
- [ ] Decide whether to keep the in-process engine or drive the `chess_ex`
      UCI executable.
- [ ] Add an option to play both sides locally (engine disabled).

### Game records and lifecycle

- [ ] Persist a game across refreshes/reconnects.
- [ ] Persist and list finished games.
- [ ] Import/export PGN and FEN.
- [ ] Add a copy-PGN action.
- [ ] Browse backward/forward through the move history.
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
- [ ] Consider a small engine option config instead of the module attribute in
      `GameLive`.

## First-pass constraints

These are deliberate for now, not bugs:

- one page, no page scrolling
- no clock/timer, settings or history navigation
- game state in the LiveView only
- default 1-ply synchronous engine move
- auto-queen promotion
- `blue` board + `gioco` pieces, with `ChessAssets` as the swap point
