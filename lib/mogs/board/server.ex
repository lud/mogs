defmodule Mogs.Board.Server.Config do
  @moduledoc false
  # Board options
  defstruct load_mode: :sync, timers: false, tracker: nil
end

defmodule Mogs.Board.Server do
  use TODO
  use GenServer, restart: :transient
  require Logger
  require Record
  alias Mogs.Board.Command.Result
  alias Mogs.Board.Server.Config
  alias Mogs.Players.Tracker

  # start_link should be called from Mogs.Board module
  @doc false
  def start_link(opts) do
    {opts, cfg_opts} = Keyword.split(opts, [:module, :id, :name, :load_info])

    mod = Keyword.fetch!(opts, :module)
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    load_info = Keyword.fetch!(opts, :load_info)

    cfg = struct(Config, cfg_opts)

    GenServer.start_link(__MODULE__, {mod, id, cfg, load_info}, name: name)
  end

  # GenServer state
  #
  # tref is a 2-tuple holding two time references : a TimeQueue tref and an
  # :erlang tref.
  defmodule S do
    defstruct id: nil, mod: nil, board: nil, tref: {nil, nil}, cfg: %Config{}, tracker: nil
  end

  # @todo allow to define the timeout from the `use Mogs.Board` call
  @timeout 60_000
  @lifecycle {:continue, :lifecycle}

  @impl true
  def init({mod, id, cfg, load_info}) do
    with {:ok, board} <- maybe_load_board(cfg, mod, id, load_info),
         {:ok, tracker} <- maybe_create_tracker(cfg) do
      continuation = init_continuation(cfg, load_info)
      state = struct(S, id: id, mod: mod, board: board, cfg: cfg, tracker: tracker)
      {:ok, state, continuation}
    end
  end

  defp maybe_load_board(%Config{load_mode: :async}, _, _, _),
    do: {:ok, nil}

  defp maybe_load_board(_, mod, id, load_info),
    do: load_board(mod, id, load_info)

  defp maybe_create_tracker(%Config{tracker: nil}),
    do: {:ok, nil}

  defp maybe_create_tracker(%Config{tracker: opts}),
    do: {:ok, Tracker.new(opts)}

  defp init_continuation(%Config{load_mode: :async}, load_info),
    do: {:continue, {:async_load, load_info}}

  defp init_continuation(_, _),
    do: @lifecycle

  @impl true
  def handle_continue({:async_load, load_info}, %S{id: id, mod: mod, board: nil} = state) do
    case load_board(mod, id, load_info) do
      {:ok, board} -> {:noreply, struct(state, board: board), @lifecycle}
      {:error, reason} -> {:stop, reason}
    end
  end

  def handle_continue(:lifecycle, state) do
    do_lifecycle(state)
  end

  @impl true
  def handle_call({:read_board_state, fun}, _from, %S{board: board} = state) do
    {:reply, fun.(board), state, @timeout}
  end

  @impl true
  def handle_call({:run_command, command}, from, %S{board: board, mod: mod} = state) do
    result = mod.handle_command(command, board)
    reply_result(result, from)
    handle_result(result, state)
  end

  @impl true
  def handle_call({:add_player, player_id, data}, from, %S{board: board, mod: mod} = state) do
    result =
      board
      |> mod.handle_add_player(player_id, data)
      |> Result.with_defaults(board: board, reply: :ok)

    reply_result(result, from)
    handle_result(result, state)
  end

  @impl true
  def handle_call({:remove_player, player_id, reason}, from, state) do
    # With the current implementation, remove player can only return :ok or
    # :stop tuples, there is no error handling, so we can always call Tracker.forget.
    tracker =
      case state.tracker do
        nil -> nil
        tracker -> Tracker.forget(tracker, player_id)
      end

    state = %S{state | tracker: tracker}

    result = player_removal(player_id, reason, state)

    reply_result(result, from)
    handle_result(result, state)
  end

  @impl true
  def handle_call({:track_player, _, _}, _from, %S{tracker: nil} = state) do
    {:reply, {:error, :no_tracker}, state, @timeout}
  end

  @impl true
  def handle_call({:track_player, player_id, pid}, _from, %S{tracker: tracker} = state) do
    tracker = Tracker.track(tracker, player_id, pid)
    {:reply, :ok, %S{state | tracker: tracker}, @timeout}
  end

  @impl true
  # Receiving a timeout for wich we have a reference in the state.
  def handle_info({:timeout, erl_tref, msg}, %S{tref: {_, erl_tref}} = state) do
    # cleanup as the ref can no longer been expected to tick
    state = %S{state | tref: {nil, nil}}

    case msg do
      :run_lifecycle -> do_lifecycle(state)
    end
  end

  @impl true
  def handle_info({:timeout, _, {Tracker, _}} = msg, %S{tracker: tracker} = state) do
    case Tracker.handle_timeout(tracker, msg) do
      :stale ->
        {:noreply, state, @timeout}

      {:player_timeout, player_id, tracker} ->
        state = %S{state | tracker: tracker}
        result = player_removal(player_id, :timeout, state)
        handle_result(result, state)
    end
  end

  @impl true
  def handle_info({:timeout, _, msg}, state) do
    Logger.debug("Ignored erl timeout #{inspect(msg)}")
    {:noreply, state, @timeout}
  end

  @impl true
  @todo "pass timeout to the board callback module"
  def handle_info(:timeout, state) do
    Logger.debug("Ignored #{inspect(__MODULE__)} :timeout")
    {:noreply, state, @timeout}
  end

  def handle_info({:DOWN, _, :process, _, _} = msg, %S{tracker: tracker} = state) do
    case Tracker.handle_down(tracker, msg) do
      {:ok, tracker} ->
        {:noreply, %S{state | tracker: tracker}, @timeout}

      :unknown ->
        Logger.warn("Received monitor down message: #{inspect(msg)}")
        {:noreply, state, @timeout}
    end
  end

  defp reply_result(result, from) do
    GenServer.reply(from, result.reply)
  end

  defp handle_result(%Result{} = result, %S{mod: mod} = state) do
    # Result has mutiple infos
    # - reply : handled outside of this function, in handle_call
    # - error (ok? :: boolean, reason :: any): We decide if we call
    #   handle_update or handle_error
    # - board: we will put the result board into our state
    # - stop: false | {true, reason :: any}

    transformed =
      if result.ok?,
        do: mod.handle_update(result.board),
        else: mod.handle_error(result.reason, result.board)

    result =
      case transformed do
        {:ok, board} -> %Result{result | board: board}
        {:stop, reason} -> %Result{result | stop: {true, reason}}
      end

    state = %S{state | board: result.board}

    case result.stop do
      {true, reason} -> {:stop, reason, state}
      false -> {:noreply, state, @lifecycle}
    end
  end

  defp handle_result(not_a_result, _state) do
    Logger.error("Command returned invalid result: #{inspect(not_a_result)}")
    exit({:bad_command_return, not_a_result})
  end

  defp load_board(mod, id, load_info) do
    case mod.load(id, load_info) do
      {:ok, board} -> {:ok, board}
      {:error, _reason} = error -> error
      other -> {:error, {:bad_return, {mod, :load, [id, load_info]}, other}}
    end
  end

  # Managing the state after different events. We implement is as a simple
  # `with` block that will call all functions of the lifecycle and expect them
  # to return `:unhandled`, and then just return {:noreply, state, timeout}
  # if any function returns {:handled, result} we will return the result.
  #
  # Any function that "consumes" the loop iteration by returning {:handled,_}
  # should return a {:continue, :lifecycle} in the reply in order to run the
  # lifecycle again and again until all clauses returns :unhandled.
  #
  # Currently we only have one function
  defp do_lifecycle(state) do
    # Syntax with multiple lifetime functions:
    # with :unhandled <- lc_run_next_timer(state),
    #      :unhandled <- fun_2(state),
    #      :unhandled <- fun_3(state),
    #      :unhandled <- fun_4(state),
    #      :unhandled <- fun_5(state) do
    #   {:noreply, state, @timeout}
    # else
    #   {:handled, gen_tuple_reply} -> gen_tuple_reply
    # end

    # Make credo happy and use a case
    case lc_run_next_timer(state) do
      :unhandled -> {:noreply, state, @timeout}
      {:handled, gen_tuple_reply} -> gen_tuple_reply
    end
  end

  # Lifecycle functions prefixed with "lc_"

  defp lc_run_next_timer(%S{cfg: %Config{timers: false}}) do
    :unhandled
  end

  defp lc_run_next_timer(%S{cfg: %Config{timers: true}} = state) do
    %S{tref: {tq_tref, erl_tref}, board: board, mod: mod} = state

    case Mogs.Timers.pop_timer(board) do
      {:ok, entry, board} ->
        timer = TimeQueue.value(entry)
        result = mod.handle_timer(timer, board)
        gen_tuple = handle_result(result, %S{state | board: board})

        {:handled, gen_tuple}

      # delay for wich we already have an erlang timer running.
      # --beware--, the tq_ref is pinned but in "when" clause we are
      # checking  erl_tref
      {:delay, ^tq_tref, _delay} when is_reference(erl_tref) ->
        :unhandled

      {:delay, new_tq_ref, delay} ->
        # We will cancel the current timer as the next TimeQueue timer is not
        # the current known one. We can do it asynchronoulsy (leaving a chance
        # for it to trigger if it would tick just now) because if we receive it,
        # we will have a new timer ref in the state so we will ignore it anyway.
        # Also we set info to false so we do not receive a cancellation message
        if is_reference(erl_tref) do
          :erlang.cancel_timer(erl_tref, async: true, info: false)
        end

        new_erl_tref = :erlang.start_timer(delay, self(), :run_lifecycle)

        {:handled, {:noreply, %S{state | tref: {new_tq_ref, new_erl_tref}}, @lifecycle}}

      :empty ->
        :unhandled
    end
  end

  defp player_removal(player_id, reason, %S{mod: mod, board: board}) do
    board
    |> mod.handle_remove_player(player_id, reason)
    |> Result.with_defaults(board: board, reply: :ok)
  end
end
