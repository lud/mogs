defmodule Mogs.Board.Command do
  @moduledoc """
  This module defines a behaviour for module-based commands that define a
  command as a struct and callbacks to handle such commands with a board.

  Adopting the behaviour with `use Mogs.Board.Command` imports the helpers to
  define a command result.
  """
  alias Mogs.Board.Command.Result
  @type command_result :: Result.t()
  @type t :: struct | {module, data :: any}

  @callback run(struct, Mogs.Board.board()) :: command_result

  defmacro __using__(_) do
    quote do
      import Mogs.Board.Command.Result, only: [return: 1]
      @behaviour unquote(__MODULE__)
    end
  end

  def run_command(%mod{} = command, board) do
    # We do not have much to do here. Just let the server crash
    case mod.run(command, board) do
      %Result{} = result ->
        result
        |> Result.put_default_board(board)

      other ->
        reason = {:bad_return, {mod, :run, [command, board]}, other}
        {:stop, {:error, reason}, reason, board}
    end
  end
end
