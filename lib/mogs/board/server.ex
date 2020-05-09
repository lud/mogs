defmodule Mogs.Board.Server.Options do
  @moduledoc false
  # Board options
  require Record
  Record.defrecord(:rcfg, timers: false)
end

defmodule Mogs.Board.Server do
  use GenServer, restart: :transient
  require Logger
  require Record
  import Mogs.Board.Server.Options, only: [rcfg: 0, rcfg: 1, rcfg: 2], warn: false
  # GenServer state
  #
  # tref is a 2-tuple holding two time references : a TimeQueue tref and an
  # :erlang tref.
  Record.defrecordp(:s, id: nil, mod: nil, board: nil, tref: {nil, nil}, cfg: rcfg())
  alias Mogs.Board.Command.Result

  # @todo allow to define the timeout from the `use Mogs.Board` call
  @timeout 60_000

  def start_link(opts) when is_list(opts) do
    {opts, cfg_opts} = Keyword.split(opts, [:mod, :id, :name, :load_info])
    mod = Keyword.fetch!(opts, :mod)
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    load_info = Keyword.fetch!(opts, :load_info)
    # debug: [:trace]
    cfg = load_board_config(cfg_opts, rcfg())
    GenServer.start_link(__MODULE__, {mod, id, load_info, cfg}, name: name)
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

  defp load_board_config_elem(k, v, cfg) do
    Logger.warn("Ignored Invalid #{__MODULE__} config options: #{inspect(k)}=#{inspect(v)}")
    cfg
  end

  @impl true
  def init({mod, id, load_info, cfg}) do
    with :sync <- load_mode(mod),
         {:ok, board} <- load_board(mod, id, load_info) do
      {:ok, s(id: id, mod: mod, board: board, cfg: cfg), {:continue, :lifecycle}}
    else
      :async ->
        {:ok, s(id: id, mod: mod, board: load_info, cfg: cfg), {:continue, :async_load}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:async_load, s(id: id, mod: mod, board: load_info) = state) do
    case load_board(mod, id, load_info) do
      {:ok, board} -> {:noreply, s(state, board: board), {:continue, :lifecycle}}
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
    handle_result(mod.handle_command(command, board), {true, from}, state)
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

  def handle_info({:timeout, _, msg}, state) do
    Logger.debug("Ignored timeout #{inspect(msg)}")
    {:noreply, state, @timeout}
  end

  defp handle_result(%Result{} = result, reply_info, s(mod: mod) = state) do
    # First, send any command reply if needed
    case reply_info do
      false -> false
      {true, gen_from} -> GenServer.reply(gen_from, result.reply)
    end

    {callback, args} =
      case result.ok? do
        true ->
          {:handle_update, [result.board]}

        false ->
          {:handle_error, [result.reason, result.board]}
      end

    case apply(mod, callback, args) do
      {:ok, board} -> {:noreply, s(state, board: board), {:continue, :lifecycle}}
      {:stop, reason} -> {:stop, reason, s(state, board: result.board)}
    end
  end

  defp handle_result(not_a_result, _, state) do
    Logger.error("Command returned invalid result: #{inspect(not_a_result)}")
    {:stop, {:bad_command_return, not_a_result}, state}
  end

  defp load_mode(mod) do
    case mod.load_mode() do
      :sync -> :sync
      :async -> :async
      other -> {:bad_return, {mod, :load_mode, []}, other}
    end
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
    s(tref: {tq_tref, erl_tref}, board: board) = state

    case Mogs.Timers.pop_timer(board) do
      {:ok, entry, board} ->
        gen_tuple =
          case TimeQueue.value(entry) do
            {:mogs_command_timer, command_mod, data} ->
              handle_result(command_mod.handle_timer(data, board), false, s(state, board: board))

            other ->
              {:stop, {:bad_timer, other}, s(state, board: board)}
          end

        {:handled, gen_tuple}

      # delay for wich we already have an erlang timer running
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

        {:handled,
         {:noreply, s(state, tref: {new_tq_ref, new_erl_tref}), {:continue, :lifecycle}}}

      # now we have a new state, so we must tell the lifecycle handler that
      # we handled something. we will just loop on the lifecycle

      :empty ->
        :unhandled
    end
  end
end
