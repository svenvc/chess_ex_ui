defmodule ChessUI.EngineTest do
  use ExUnit.Case, async: true

  alias ChessUI.Engine

  test "description lists the options without the word strategy" do
    description = Engine.description()

    assert description =~ "best"
    assert description =~ "book off"
    refute description =~ "strategy"
  end
end
