defmodule Mogs.Board.Callbacks do
  @moduledoc """
  Defines a `defaults()` macro that adds default callbacks implementations to
  a module.

  Usage

      defmodule MyBoard do
        @behaviour Mogs.Board
        Mogs.Board.Callbacks.defaults()

      end

  """
  defmacro defaults() do
    quote do
      @spec server_name(id :: pid | any) ::
              pid | {:via, Registry, {Mogs.Board.Registry, id :: any}}
      def server_name(pid) when is_pid(pid),
        do: pid

      def server_name(id),
        do: {:via, Registry, {Mogs.Board.Registry, id}}

      defoverridable server_name: 1

      @spec handle_command(command :: any, board :: any) :: Mogs.Board.Command.Result.t()
      def handle_command(command, board) do
        Mogs.Board.__handle_command__(command, board)
      end

      defoverridable handle_command: 2

      @spec handle_timer(timer, board) :: Mogs.Board.Command.Result.t()
            when board: any,
                 timer: {:mogs_command_timer, command_mod :: atom, data :: any}
      def handle_timer(timer, board) do
        Mogs.Board.__handle_timer__(timer, board)
      end

      defoverridable handle_timer: 2
    end
  end
end
