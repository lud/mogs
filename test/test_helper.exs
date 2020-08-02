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
end
