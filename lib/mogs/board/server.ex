defmodule Mogs.Board.Server.Config do
  @moduledoc false
  # Board options
  require Record
  Record.defrecord(:rcfg, timers: false, tracker: nil)
end

defmodule Mogs.Board.Server do
  use TODO
  use GenServer, restart: :transient
  require Logger
  require Record
  alias Mogs.Board.Command.Result
  alias Mogs.Players.Tracker
  import Mogs.Board.Server.Config, only: [rcfg: 0, rcfg: 1, rcfg: 2], warn: false
  # GenServer state
  #
  # tref is a 2-tuple holding two time references : a TimeQueue tref and an
  # :erlang tref.
  Record.defrecordp(:s, id: nil, mod: nil, board: nil, tref: {nil, nil}, cfg: rcfg(), tracker: nil)

  # @todo allow to define the timeout from the `use Mogs.Board` call
  @timeout 60_000
  @lifecycle {:continue, :lifecycle}

  @todo "Proper options validation must be done here, it is the last moment to set defaults"

  def start_link(opts) when is_list(opts) do
    {opts, cfg_opts} = Keyword.split(opts, [:mod, :id, :name, :load_info])
    mod = Keyword.fetch!(opts, :mod)
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    load_info = Keyword.get(opts, :load_info, nil)
    cfg = load_board_config(cfg_opts, rcfg())

    tracker =
      case rcfg(cfg, :tracker) do
        nil -> nil
        tracker_opts when is_list(tracker_opts) -> Tracker.new(tracker_opts)
      end

    GenServer.start_link(__MODULE__, {mod, id, load_info, cfg, tracker}, name: name)
  end

  defp load_board_config([], cfg) do
    cfg
  end

  defp load_board_config([{k, v} | opts], cfg) do
    load_board_config(opts, load_board_config_elem(k, v, cfg))
  end

  defp load_board_config_elem(:timers, v, cfg) when is_boolean(v) do
    rcfg(cfg, timers: v)
  end

  defp load_board_config_elem(:tracker, v, cfg) when is_list(v) do
    rcfg(cfg, tracker: v)
  end

  defp load_board_config_elem(:tracker, nil, cfg) do
    rcfg(cfg, tracker: nil)
  end

  defp load_board_config_elem(k, v, cfg) do
    Logger.warn("Ignored Invalid #{__MODULE__} config options: #{inspect(k)}=#{inspect(v)}")
    cfg
  end

  @impl true
  def init({mod, id, load_info, cfg, tracker}) do
    with :sync <- load_mode(mod),
         {:ok, board} <- load_board(mod, id, load_info) do
      {:ok, s(id: id, mod: mod, board: board, cfg: cfg, tracker: tracker), @lifecycle}
    else
      :async ->
        {:ok, s(id: id, mod: mod, board: load_info, cfg: cfg, tracker: tracker),
         {:continue, :async_load}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:async_load, s(id: id, mod: mod, board: load_info) = state) do
    case load_board(mod, id, load_info) do
      {:ok, board} -> {:noreply, s(state, board: board), @lifecycle}
      {:error, reason} -> {:stop, reason}
    end
  end

  def handle_continue(:lifecycle, state) do
    do_lifecycle(state)
  end

  @impl true
  def handle_call({:read_board_state, fun}, _from, s(board: board) = state) do
    {:reply, fun.(board), state, @timeout}
  end

  @impl true
  def handle_call({:run_command, command}, from, s(board: board, mod: mod) = state) do
    result = mod.handle_command(command, board)
    reply_result(result, from)
    handle_result(result, state)
  end

  @impl true
  def handle_call({:add_player, player_id, data, pid}, from, s(board: board, mod: mod) = state) do
    result =
      board
      |> mod.handle_add_player(player_id, data)
      |> Result.with_defaults(board: board, reply: :ok)

    state =
      if result.ok? do
        case pid do
          nil ->
            state

          pid when is_pid(pid) ->
            tracker =
              s(state, :tracker)
              |> Tracker.track(player_id, pid)

            s(state, tracker: tracker)
        end
      else
        state
      end

    reply_result(result, from)
    handle_result(result, state)
  end

  @impl true
  def handle_call({:remove_player, player_id, reason, clear?}, from, state) do
    s(tracker: tracker) = state

    state =
      case clear? do
        true ->
          tracker = Tracker.forget(tracker, player_id)
          s(state, tracker: tracker)

        false ->
          state
      end

    result = player_removal(player_id, reason, state)
    reply_result(result, from)
    handle_result(result, state)
  end

  @impl true
  def handle_call({:track_player, player_id, pid}, _from, s(tracker: tracker) = state) do
    tracker = Tracker.track(tracker, player_id, pid)
    {:reply, :ok, s(state, tracker: tracker), @timeout}
  end

  @impl true
  # Receiving a timeout for wich we have a reference in the state.
  def handle_info({:timeout, erl_tref, msg}, s(tref: {_, erl_tref}) = state) do
    # cleanup as the ref can no longer been expected to tick
    state = s(state, tref: {nil, nil})

    case msg do
      :run_lifecycle -> do_lifecycle(state)
    end
  end

  @impl true
  def handle_info({:timeout, _, {Tracker, _}} = msg, s(tracker: tracker) = state) do
    case Tracker.handle_timeout(tracker, msg) do
      :stale ->
        {:noreply, state, @timeout}

      {:player_timeout, player_id, tracker} ->
        state = s(state, tracker: tracker)
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

  def handle_info({:DOWN, _, :process, _, _} = msg, s(tracker: tracker) = state) do
    case Tracker.handle_down(tracker, msg) do
      {:ok, tracker} ->
        {:noreply, s(state, tracker: tracker), @timeout}

      :unknown ->
        Logger.warn("Received monitor down message: #{inspect(msg)}")
        {:noreply, state, @timeout}
    end
  end

  defp reply_result(result, from) do
    GenServer.reply(from, result.reply)
  end

  defp handle_result(%Result{} = result, s(mod: mod) = state) do
    # Result has mutiple infos
    # - reply : handled outside of this function, in handle_call
    # - error (ok? :: boolean, reason :: any): We decide if we call
    #   handle_update or handle_error
    # - board: we will put the result board into our state
    # - stop: false | {true, reason :: any}

    transformed =
      case result.ok? do
        true -> mod.handle_update(result.board)
        false -> mod.handle_error(result.reason, result.board)
      end

    result =
      case transformed do
        {:ok, board} -> %Result{result | board: board}
        {:stop, reason} -> %Result{result | stop: {true, reason}}
      end

    state = s(state, board: result.board)

    case result.stop do
      {true, reason} -> {:stop, reason, state}
      false -> {:noreply, state, @lifecycle}
    end
  end

  defp handle_result(not_a_result, state) do
    Logger.error("Command returned invalid result: #{inspect(not_a_result)}")
    {:stop, {:bad_command_return, not_a_result}, state}
  end

  defp load_mode(mod) do
    mod.__mogs__(:load_mode)
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
    # with :unhandled <- lf_run_next_timer(state),
    #      :unhandled <- fun_2(state),
    #      :unhandled <- fun_3(state),
    #      :unhandled <- fun_4(state),
    #      :unhandled <- fun_5(state) do
    #   {:noreply, state, @timeout}
    # else
    #   {:handled, gen_tuple_reply} -> gen_tuple_reply
    # end

    # Make credo happy and use a case
    case lf_run_next_timer(state) do
      :unhandled -> {:noreply, state, @timeout}
      {:handled, gen_tuple_reply} -> gen_tuple_reply
    end
  end

  # Lifecycle functions prefixed with "lf_"

  defp lf_run_next_timer(s(cfg: rcfg(timers: false))) do
    :unhandled
  end

  defp lf_run_next_timer(s(cfg: rcfg(timers: true)) = state) do
    s(tref: {tq_tref, erl_tref}, board: board, mod: mod) = state

    case Mogs.Timers.pop_timer(board) do
      {:ok, entry, board} ->
        timer = TimeQueue.value(entry)
        result = mod.handle_timer(timer, board)
        gen_tuple = handle_result(result, s(state, board: board))

        {:handled, gen_tuple}

      # delay for wich we already have an erlang timer running.
      # --beware--, the tq_ref is pinned but in "when" clause we are
      # checking  erl_tref
      {:delay, ^tq_tref, _delay} when is_reference(erl_tref) ->
        :unhandled

      {:delay, new_tq_ref, delay} ->
        # We will cancel the current timer as the next timequeue timer is not
        # the previous known one. We can do it asynchronoulsy (leaving a chance
        # for it to trigger if it would tick just now) because if we receive it,
        # we will have a new timer ref in the state so we will ignore it anyway.
        # Also we set info to false so we do not receive a cancellation message
        if is_reference(erl_tref) do
          :erlang.cancel_timer(erl_tref, async: true, info: false)
        end

        # our message will just be to run the lifecycle.
        new_erl_tref = :erlang.start_timer(delay, self(), :run_lifecycle)

        {:handled, {:noreply, s(state, tref: {new_tq_ref, new_erl_tref}), @lifecycle}}

      # now we have a new state, so we must tell the lifecycle handler that
      # we handled something. we will just loop on the lifecycle

      :empty ->
        :unhandled
    end
  end

  defp player_removal(player_id, reason, s(mod: mod, board: board)) do
    board
    |> mod.handle_remove_player(player_id, reason)
    |> Result.with_defaults(board: board, reply: :ok)
  end
end
