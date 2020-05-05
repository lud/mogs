defmodule Mogs.Board.Command do
  @moduledoc """
  This module defines a behaviour for module-based commands that define a
  command as a struct and callbacks to handle such commands with a board.

  Adopting the behaviour with `use Mogs.Board.Command` defines default
  implementations for most callbacks.
  """
  @type command_result :: Mogs.Board.Command.Result.t()
  @type t :: struct | {module, data :: any}

  # A command following the behaviour shall only receive struct commands.
  # Actually only structs of its own module.
  @callback run_command(struct, board :: any) :: command_result
end
