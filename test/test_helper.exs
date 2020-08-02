ExUnit.start()

defmodule Mogs.TestHelper do
  # Unlike assert_receive that awaits a message matching a pattern,
  # assert_next_receive will match a pattern against the message
  # received first. Used to check order of messages
  defmacro assert_next_receive(pattern, timeout \\ 1000) do
    quote do
      receive do
        unquote(pattern) ->
          assert true

        other ->
          flunk(
            "Expected to receive a message matching #{Macro.to_string(unquote(pattern))}, received: #{
              inspect(other)
            }"
          )
      after
        unquote(timeout) ->
          raise "timeout"
      end
    end
  end

  defmacro suppress_callback_warnings() do
    quote do
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(env) do
    Mogs.Board.behaviour_info(:callbacks)
    |> Enum.filter(fn cb -> not Module.defines?(env.module, cb) end)
    |> Enum.map(fn {fun, arity} ->
      quote do
        def unquote(fun)(unquote_splicing(for(_ <- 1..arity, do: Macro.var(:_, __MODULE__)))) do
          raise "Unimplemented callback in test in #{unquote(env.module)}"
        end
      end
    end)
  end
end
