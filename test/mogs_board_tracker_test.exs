defmodule Mogs.Players.TrackerTest do
  use ExUnit.Case, async: true
  alias Mogs.Players.Tracker

  @test_timeout 100

  defmodule TrackBoard do
    defstruct players: %{}, test_process_pid: nil
    use Mogs.Board, tracker: [timeout: 100]

    def load(_, {:parent, pid} = _load_info) when is_pid(pid) do
      {:ok, struct(__MODULE__, test_process_pid: pid)}
    end

    def handle_add_player(board, player_id, data) do
      case Map.get(board.players, player_id) do
        nil ->
          IO.puts("Adding player #{inspect(player_id)}")
          {:ok, put_in(board.players[player_id], data)}

        _ ->
          {:error, :already_in}
      end
    end

    def handle_player_timeout(board, player_id) do
      %__MODULE__{test_process_pid: pid} = board
      send(pid, {:player_left, player_id})
      {:stop, :normal}
    end
  end

  setup_all do
    start_supervised(TrackBoard.Supervisor)
    :ok
  end

  test "a tracker can be started and monitor players with a timeout" do
    id = __ENV__.line
    player_id = 1

    assert {:ok, pid} = TrackBoard.start_server(id, load_info: {:parent, self()})

    Process.sleep(1000)

    assert pid === GenServer.whereis(TrackBoard.__name__(id))

    spawn_tracked_player = fn player_id ->
      spawn(fn ->
        case TrackBoard.add_player(id, player_id, :some_data) do
          :ok -> :ok
          {:error, :already_in} -> TrackBoard.track_player(id, player_id)
        end

        Process.sleep(:infinity)
      end)
    end

    # Then we will start/kill the player multiple times. As long
    # as a player is re-tracked within the timeout limit, we will
    # receive no message
    iterations = 10
    wait_time = 100

    this = self()

    spawn(fn ->
      for _ <- 1..10 do
        player_1 = spawn_tracked_player.(:p1)
        Process.sleep(wait_time)
        Process.exit(player_1, :kill)
      end

      send(this, :finished_iteration)
    end)

    # On spawn the process is tracked, and the it is killed after `wait_time`
    # We will have to wait iterations * wait_time for the :finished_iteration
    # message.
    # And then wait at least @test_timeout to get the player timeout.

    assert_receive(:finished_iteration, wait_time * iterations + 50)

    # now we should receive the left message but not before the actual player
    # timeout time
    refute_received({:player_left, :p1}, "Received timeout too early")
    assert_receive({:player_left, :p1}, @test_timeout + 50)
    Process.sleep(100)
    # The board stops explicitly
    assert false === Process.alive?(pid)
  end
end
