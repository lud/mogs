defmodule TestHelpers.NoWarnings do
  defmacro __name__() do
    quote do
      def __name__(pid) when is_pid(pid) do
        pid
      end

      def __name__(board_id) do
        nil
      end
    end
  end

  defmacro handle_update() do
    quote do
      def handle_update(board) do
        {:ok, board}
      end
    end
  end

  defmacro fake_fun(name, arity) do
    args = List.duplicate(quote(do: _), arity)
    mod = __CALLER__.module

    quote do
      def unquote(name)(unquote_splicing(args)) do
        raise "Undefined test module fun #{unquote(name)}/#{unquote(arity)} in #{
                inspect(unquote(mod))
              }"
      end
    end
  end

  defmacro handle_add_player() do
    quote do
      def handle_add_player(_, _, _) do
        raise "Unimplemented"
      end
    end
  end
end

ExUnit.start()
