defprotocol Mogs.Board.Timers do
  # Mogs types
  @type t :: term
  @type timer :: {handler :: module, data :: term}

  # Borrowed types
  @type timers :: TimeQueue.t()
  @type timestamp_ms :: TimeQueue.timestamp_ms()
  @type ttl :: TimeQueue.ttl()
  @type pop_return :: TimeQueue.pop_return(t)
  @type enqueue_return :: TimeQueue.enqueue_return(t)

  @fallback_to_any true

  @spec pop_timer(t, now :: timestamp_ms()) :: pop_return
  def pop_timer(board, now)

  @spec enqueue_timer(t, ttl, timer, now :: timestamp_ms()) :: enqueue_return
  def enqueue_timer(board, ttl, timer, now)

  # @spec put_timers(t, timers) :: t
  # def put_timers(board, timers)
end

defimpl Mogs.Board.Timers, for: Any do
  defmacro __deriving__(module, struct, options) do
    case find_key(struct, options) do
      {:raise, exception, message} ->
        quote do
          reraise unquote(exception),
                  [message: unquote(message)],
                  unquote(Macro.escape(Macro.Env.stacktrace(__CALLER__)))
        end

      {:ok, key} ->
        quote do
          defimpl Mogs.Board.Timers, for: unquote(module) do
            @type timestamp_ms :: Mogs.Board.Timers.timestamp_ms()
            @type timers :: Mogs.Board.Timers.timers()
            @type timer :: Mogs.Board.Timers.timer()
            @type ttl :: Mogs.Board.Timers.ttl()
            @type pop_return :: Mogs.Board.Timers.pop_return()
            @type enqueue_return :: Mogs.Board.Timers.enqueue_return()
            @type impl :: %{:__struct__ => unquote(module), unquote(key) => timers}

            @spec pop_timer(impl, now :: timestamp_ms) :: pop_return
            def pop_timer(board, now) do
              case TimeQueue.pop(Map.fetch!(board, unquote(key)), now) do
                {:ok, entry, tq} -> {:ok, entry, Map.put(board, unquote(key), tq)}
                other -> other
              end
            end

            @spec enqueue_timer(impl, ttl, timer, now :: timestamp_ms()) :: enqueue_return()
            def enqueue_timer(board, ttl, timer, now) do
              {:ok, tref, tq} =
                TimeQueue.enqueue(Map.fetch!(board, unquote(key)), ttl, timer, now)

              {:ok, tref, Map.put(board, unquote(key), tq)}
            end

            # @spec put_timers(impl, timers) :: impl
            # def put_timers(board, timers) do
            #   Mogs.Board.put_timers(board, unquote(key), timers)
            # end
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
          @derive {#{@protocol}, key: my_key}
          defstruct my_key: Mogs.Board.timers()

      If you don't own the struct you may use Protocol.derive/3 placed outside \
      of any module:

          Protocol.derive(#{@protocol}, #{inspect(name)}, key: :my_key)
      """
  end

  defp raise_unimplemented(value) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: value,
      description: "#{@protocol} protocol must always be explicitly implemented"
  end

  def pop_timer(value, _) do
    raise_unimplemented(value)
  end

  def enqueue_timer(value, _, _, _) do
    raise_unimplemented(value)
  end

  # def put_timers(value, _) do
  #   raise_unimplemented(value)
  # end

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
         A :key option is required when deriving Mogs.Board.Timers:
           @derive {Mogs.Board.Timers, key: :my_key}
           defstruct my_key: Mogs.Board.timers(), other_key: …
         """}
    end
  end
end
