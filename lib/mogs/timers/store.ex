defprotocol Mogs.Timers.Store do
  # Mogs types
  @type t :: term
  @type timers :: Mogs.Timers.t()

  @fallback_to_any true

  @spec get_timers(t) :: timers
  def get_timers(board)

  @spec put_timers(t, timers) :: t
  def put_timers(board, timers)
end

defimpl Mogs.Timers.Store, for: Any do
  defmacro __deriving__(module, struct, options) do
    case find_key(struct, options) do
      {:raise, exception, message} ->
        quote do
          reraise unquote(exception),
                  [message: unquote(message)],
                  unquote(Macro.escape(Macro.Env.stacktrace(__CALLER__)))
        end

      {:ok, key} ->
        quote location: :keep do
          defimpl unquote(@protocol), for: unquote(module) do
            @type timers :: Mogs.Timers.t()
            @type impl :: %{:__struct__ => unquote(module), unquote(key) => timers}

            @spec get_timers(impl) :: timers
            def get_timers(board) do
              Map.fetch!(board, unquote(key))
            end

            @spec put_timers(impl, timers) :: impl
            def put_timers(board, timers) do
              Map.put(board, unquote(key), timers)
            end
          end
        end
    end
  end

  defp raise_unimplemented(%name{} = struct) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: """
      #{@protocol} protocol must always be explicitly implemented.

      If you own the struct, you can derive the implementation specifying \
      the key where timers must be stored:

        defmodule #{inspect(name)} do
          @derive {#{inspect(@protocol)}, key: timers}
          defstruct timers: Mogs.Timers.new()

      If you don't own the struct you may use Protocol.derive/3 placed outside \
      of any module:

          Protocol.derive(#{inspect(@protocol)}, #{inspect(name)}, key: :timers)
      """
  end

  defp raise_unimplemented(value) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: value,
      description: "#{@protocol} protocol must always be explicitly implemented"
  end

  def get_timers(value) do
    # Dialyzer trick
    case :erlang.phash2(1, 1) do
      0 -> raise_unimplemented(value)
      # This code will NEVER be executed
      1 -> TimeQueue.new()
    end
  end

  def put_timers(value, _) do
    # Dialyzer trick
    case :erlang.phash2(1, 1) do
      0 -> raise_unimplemented(value)
      # This code will NEVER be executed
      1 -> value
    end
  end

  defp find_key(%{__struct__: name} = struct, key) when is_atom(key) do
    if key in Map.keys(struct),
      do: {:ok, key},
      else: {:raise, ArgumentError, "key #{key} not found in struct #{name}"}
  end

  defp find_key(struct, options) when is_list(options) do
    case Keyword.fetch(options, :key) do
      {:ok, key} ->
        find_key(struct, key)

      :error ->
        {:raise, ArgumentError,
         """
         A :key option is required when deriving Mogs.Timers:
           @derive {Mogs.Timers.Store, key: :timers}
           defstruct timers: Mogs.Timers.new(), other_key: …
         """}
    end
  end
end
