defmodule Mogs.Timers do
  alias Mogs.Timers.Store
  @type board :: Store.t()

  # Borrowed types
  @type t :: TimeQueue.t()
  @type timer :: term
  @type timestamp_ms :: TimeQueue.timestamp_ms()
  @type ttl :: TimeQueue.ttl()
  @type pop_return :: TimeQueue.pop_return(board)
  @type enqueue_return :: TimeQueue.enqueue_return(board)

  @doc """
  Returns an empty timers structure to initialize timers in a board. This
  structure will contain the timers that commands may set on the board.

  The timers (implemented by the TimeQueue module) can be serialized (e.g with
  term_to_binary)
  """
  @spec new :: Mogs.Timers.t()
  def new() do
    TimeQueue.new()
  end

  @spec enqueue_timer(board, ttl, value :: any, now :: integer) :: enqueue_return
  def enqueue_timer(board, ttl, value, now \\ TimeQueue.now())

  def enqueue_timer(board, ttl, value, now) do
    Store.enqueue_timer(board, ttl, value, now)
  end

  @spec pop_timer(board, now :: integer) :: pop_return
  def pop_timer(board, now \\ TimeQueue.now())

  def pop_timer(board, now) do
    Store.pop_timer(board, now)
  end
end

defprotocol Mogs.Timers.Store do
  alias Mogs.Timers
  # Mogs types
  @type t :: term

  @fallback_to_any true

  @spec pop_timer(t, now :: Timers.timestamp_ms()) :: Timers.pop_return()
  def pop_timer(board, now)

  @spec enqueue_timer(t, Timers.ttl(), Timers.timer(), now :: Timers.timestamp_ms()) ::
          Timers.enqueue_return()
  def enqueue_timer(board, ttl, timer, now)

  # @spec put_timers(t, timers) :: t
  # def put_timers(board, timers)
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
        quote do
          defimpl unquote(@protocol), for: unquote(module) do
            @type timestamp_ms :: Mogs.Timers.timestamp_ms()
            @type timers :: Mogs.Timers.t()
            @type timer :: Mogs.Timers.timer()
            @type ttl :: Mogs.Timers.ttl()
            @type pop_return :: Mogs.Timers.pop_return()
            @type enqueue_return :: Mogs.Timers.enqueue_return()
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
          defstruct my_key: Mogs.timers()

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
    # Dialyzer trick
    case :erlang.phash2(1, 1) do
      0 ->
        raise_unimplemented(value)

      1 ->
        # This code will NEVER be executed
        TimeQueue.pop(TimeQueue.new())
        |> case do
          :empty -> :empty
          q -> put_elem(q, 2, value)
        end
    end
  end

  def enqueue_timer(value, _, _, _) do
    # Dialyzer trick
    case :erlang.phash2(1, 1) do
      0 -> raise_unimplemented(value)
      # This code will NEVER be executed
      1 -> TimeQueue.enqueue(TimeQueue.new(), 0, nil) |> put_elem(2, value)
    end
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
         A :key option is required when deriving Mogs.Timers:
           @derive {Mogs.Timers.Store, key: :my_key}
           defstruct my_key: Mogs.timers(), other_key: …
         """}
    end
  end
end
