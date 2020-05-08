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

      # start_timer with custom "now" is not supported actually because the
      # Mogs.Board.Server cannot know wich custom 'now()' use.
      # That could be a callback from the board mod but that is unlikely needed.
      @spec start_timer(Mogs.Timers.board(), Mogs.Timers.ttl(), data :: any) ::
              {:ok, Mogs.Timers.board()}
      defp start_timer(board, ttl, data) do
        timer = {:mogs_command_timer, __MODULE__, data}
        {:ok, _, board} = Mogs.Timers.enqueue_timer(board, ttl, timer)
        {:ok, board}
      end

      def handle_timer(_data, _board) do
        raise UndefinedFunctionError, """
        handle_timer/2 is not defined for module #{__MODULE__}.

        If you want to use the `start_timer/3` functions from a command, you
        need to implement handle_timer/2:

          @spec handle_timer(data :: any, board :: any) :: Mogs.Board.Command.Result.t()
          def handle_timer(data, board) do

          end

        It must return a Mogs.Board.Command.Result (generally using the return/1)
        function available in command modules.
        Note that any `:reply` set in this result will be ignored as timers are
        not handled within the scope of a call by the board server.
        """
      end

      defoverridable handle_timer: 2
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
