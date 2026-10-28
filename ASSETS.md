# Third-party assets

The chess board and piece images are vendored from
[lichess-org/lila](https://github.com/lichess-org/lila) at commit
`ffa4be8221645f143b05948dd591545f2b004225`.

| Files | Source | Author(s) | License |
| --- | --- | --- | --- |
| `priv/static/images/boards/blue.png` | `public/images/board/blue.png` | the lila authors and [pirouetti](https://lichess.org/@/pirouetti) | [AGPLv3+](https://github.com/lichess-org/lila/blob/master/LICENSE) |
| `priv/static/images/pieces/gioco/*.svg` | `public/piece/gioco/*.svg` | [sadsnake1](https://lichess.org/@/sadsnake1) | [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) |

The source code of this project is MIT licensed. The vendored assets keep
their original licenses; in particular the Gioco piece set is licensed for
non-commercial use.

The assets are looked up through `ChessUIWeb.ChessAssets`, so another board
theme or piece set can be added later without changing the board component.
