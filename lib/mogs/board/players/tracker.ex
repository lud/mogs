defmodule Mogs.Players.Tracker do
  require Record
  require Logger
  @sup Mogs.Players.Tracker.DynamicSupervisor
  @default_player_timeout 30_000

  @opts_schema %{timeout: [type: :integer, required: true, default: @default_player_timeout]}
  def validate_opts(opts) when is_list(opts) do
    KeywordValidator.validate(opts, @opts_schema)
  end

  def validate_parent_opts(:tracker, false) do
    []
  end

  def validate_parent_opts(:tracker, opts) when is_list(opts) do
    case validate_opts(opts) do
      {:ok, _} -> []
      {:error, invalid} -> Keyword.values(invalid)
    end
  end

  def validate_parent_opts(:tracker, opts) do
    ["Keyword required, got: #{inspect(opts)}"]
  end

  # - p2ms: a map from 1 player_in to N monitor_refs
  # - m2p: a map from 1 monitor_ref to 1 player_id
  # - ptimeout: a timeout (integer) indicating the time after which we
  #   will consider that a player has left when there is no alive
  #   tracked process for them.
  # - p2tref: a map from 1 player_id to 1 erlang timeout tref. It is
  #   important to keep the reference of a timer to prevent race
  #   conditions: If a player has no alive process and we start a
  #   timer for 30 seconds. Then at ~30 seconds the timer fires but we
  #   also receive a new process for the player, and immediately after
  #   this process exits (starting a new timer). The player should be
  #   considered alive for 30 more seconds, so we need a way to
  #   discard the first timer as it is not relevant anymore.
  @todo "remove client in schema"
  @todo "change record name or use a man do differ from server s()"
  Record.defrecordp(:s, client: nil, p2ms: %{}, m2p: %{}, p2tref: %{}, ptimeout: nil)
  @type monitor :: reference()
  @type player_id :: term()

  @hibernate_timeout 40_000

  @opts_schema %{
    timeout: [type: :integer, default: @default_player_timeout]
  }

  def new(opts) do
    opts = KeywordValidator.validate!(opts, @opts_schema)
    s(ptimeout: Keyword.fetch!(opts, :timeout))
  end

  import GenServer, only: [call: 2]

  def track(s(p2ms: p2ms, m2p: m2p) = state, player_id, pid) when is_pid(pid) do
    Logger.debug("Monitoring process #{inspect(pid)} for player #{inspect(player_id)}")
    ref = Process.monitor(pid)
    p2ms = Map.update(p2ms, player_id, [ref], fn refs -> [ref | refs] end)
    m2p = Map.put(m2p, ref, player_id)
    state = maybe_cancel_timeout(state, player_id)
    s(state, p2ms: p2ms, m2p: m2p)
  end

  def forget(tracker, player_id) do
    call(tracker, {:forget, player_id})
  end

  def start_link(opts) when is_list(opts) do
    with {:ok, opts} <- KeywordValidator.validate(opts, @opts_schema) do
      GenServer.start_link(__MODULE__, opts, debug: [])
    end
  end

  def handle_call({:forget, player_id}, _from, s(p2ms: p2ms, m2p: m2p, p2tref: p2tref) = state) do
    {p2ms, m2p} =
      case Map.pop(p2ms, player_id) do
        {nil, _} ->
          {p2ms, m2p}

        {refs, new_p2ms} ->
          # delete all monitors for this player
          Enum.each(refs, &Process.demonitor(&1, [:flush]))
          {_, new_m2p} = Map.split(m2p, refs)
          {new_p2ms, new_m2p}
      end

    # Delete the running timeout if any
    state = maybe_cancel_timeout(state, player_id)

    {:reply, :ok, s(state, p2ms: p2ms, m2p: m2p, p2tref: p2tref), @hibernate_timeout}
  end

  # Cancels any timeout present in p2tref for player_id and also deletes
  # the player_id key from the p2tref map
  defp maybe_cancel_timeout(s(p2tref: p2tref) = state, player_id)
       when is_map_key(p2tref, player_id) do
    {ref, p2tref} = Map.pop(p2tref, player_id)

    case ref do
      nil -> :ok
      ref -> :erlang.cancel_timer(ref, async: false)
    end

    s(state, p2tref: p2tref)
  end

  # No timeout to cancel
  defp maybe_cancel_timeout(state, _) do
    state
  end

  # Client is down
  def handle_info({:DOWN, ref, :process, pid, reason}, s(client: {pid, ref}) = state) do
    # Stop with the same reason. No restart expected as we are a
    # temporary process.
    {:stop, reason, state}
  end

  # A tracked process is down
  def handle_info({:DOWN, ref, :process, _pid, _}, s(m2p: m2p) = state)
      when is_map_key(m2p, ref) do
    s(m2p: m2p, p2ms: p2ms, p2tref: p2tref, ptimeout: delay) = state
    {player_id, m2p} = Map.pop(m2p, ref)

    # remove the current ref from the player's refs. If there is
    # no more ref left we will start a timer to check the player
    # again after a timeout
    {has_refs?, p2ms} =
      Map.get_and_update(p2ms, player_id, fn refs ->
        case List.delete(refs, ref) do
          [] -> {false, []}
          new_refs -> {true, new_refs}
        end
      end)

    state = s(state, p2ms: p2ms, m2p: m2p)

    # Start the timer and register it in state
    state =
      if has_refs? do
        state
      else
        Logger.debug("Start erlang timer for #{delay}ms")
        tref = :erlang.start_timer(delay, self(), {:check_player, player_id})
        s(state, p2tref: Map.put(p2tref, player_id, tref))
      end

    {:noreply, state, @hibernate_timeout}
  end

  def handle_info({:timeout, ref, {:check_player, player_id}}, s(p2tref: p2tref) = state)
      when is_map_key(p2tref, player_id) and ref == :erlang.map_get(player_id, p2tref) do
    s(p2ms: p2ms, p2tref: p2tref, client: {client_pid, _}) = state
    # We receive a timeout for a player, and since this timeout ref is
    # in our state it means the player was not tracked since we
    # started the timer, so the player actually left
    p2tref = Map.delete(p2tref, player_id)
    p2ms = Map.delete(p2ms, player_id)
    state = s(state, p2tref: p2tref, p2ms: p2ms)
    # We will inform the client that the player left
    send(client_pid, {__MODULE__, :player_timeout, player_id})
    {:noreply, state, @hibernate_timeout}
  end

  def handle_info({:timeout, _ref, {:check_player, _}}, state) do
    # Ignore state timeout
    {:noreply, state, @hibernate_timeout}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, state) do
    # Monitor ref is unknown
    Logger.error("Unknown monitor reference: #{inspect(ref)} pid: #{inspect(pid)}")
    {:noreply, state, @hibernate_timeout}
  end

  def handle_info(:timeout, state) do
    {:noreply, state, :hibernate}
  end

  def handle_info(msg, state) do
    Logger.error("Unhandled info in #{__MODULE__}: #{inspect(msg)}")
    {:noreply, state}
  end
end
