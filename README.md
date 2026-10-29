# ChessEx UI

A Phoenix LiveView web interface for playing chess against the pure Elixir
[ChessEx](https://github.com/svenvc/chess_ex) engine.

## Requirements

- Elixir `~> 1.15`

## Setup

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000/> for the board. `/game` serves the same page as an
alias.

## Playing

- You play White by default. The engine answers with a 4-ply search and uses the
  opening book when the position is known; it thinks in the background while
  the turn indicator shows the progress.
- Click a piece and then a highlighted legal target. Clicking another own
  piece changes the selection; clicking the selected square clears it.
- The selected square, legal destinations, capture targets and the last move
  are highlighted. A king in check glows red.
- File labels are below the board and rank labels to the left. Both reverse
  when you switch sides.
- **New game** resets the board. **Switch sides** starts a new game as the other
  color; if the engine is now White, it opens immediately. **Resign** ends the
  current game.
- The side panel contains the `Chess.Narrator` status, recent activity and a
  PGN-style move list.
- The page is sized to fit one viewport without page scrolling; the side panels
  scroll internally when needed.

Current first-pass limits:

- Promotion automatically promotes to a queen.
- Game state lives in the LiveView; refreshing or reconnecting starts over.
- There is no clock, settings UI or history navigation.

## Project structure

| Path | Purpose |
| --- | --- |
| `lib/chess_ex_ui_web/live/game_live.ex` | `/` LiveView (also `/game`): state, clicks, engine turns, status and notation |
| `lib/chess_ex_ui/engine.ex` | Engine strength and book options; test seam for the engine module |
| `lib/chess_ex_ui_web/components/chess_board.ex` | Presentational board, squares, coordinates and highlights |
| `lib/chess_ex_ui_web/chess_assets.ex` | Board/piece asset lookup and theme seam |
| `lib/chess_ex_ui_web/components/layouts.ex` | App shell; `bare` omits the header for the game page |
| `assets/css/app.css` | Tailwind entry point and the board-surface rule |
| `priv/static/images/boards/blue.png` | Vendored lichess board texture |
| `priv/static/images/pieces/gioco/` | Vendored lichess Gioco piece set |

## Development

```sh
mix precommit    # compile with warnings as errors, format, run tests
mix assets.build # rebuild Tailwind and esbuild
```

The LiveView tests cover board rendering, coordinate orientation, selection and
legal targets, legal move application, the asynchronous engine reply and thinking
state, illegal clicks, switching sides, starting over and resigning.

See [TODO.md](TODO.md) for known first-pass limits and planned work.

## Assets and licensing

The board and pieces are vendored from
[lichess-org/lila](https://github.com/lichess-org/lila) and are not hotlinked.
See [ASSETS.md](ASSETS.md) for the pinned commit, authors and licenses. The
project code is MIT licensed; the assets keep their own licenses. The Gioco
piece set is CC BY-NC-SA 4.0, so it is not suitable for commercial use as-is.
