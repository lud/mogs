defmodule Mogs.Board.Command.ResultTest do
  use ExUnit.Case, async: true
  alias Mogs.Board.Command.Result
  doctest Result
  import Result, only: [return: 1, return: 2], warn: false

  test "the return function is versatile" do
    assert %{reply: {:error, "badstuff"}, ok?: false} = return(error: "badstuff")

    assert %{reply: "detail", ok?: false, reason: "badstuff"} =
             return(error: "badstuff", reply: "detail")

    assert %{reply: "detail", ok?: false, reason: "badstuff"} =
             return(reply: "detail", error: "badstuff")
  end
end
