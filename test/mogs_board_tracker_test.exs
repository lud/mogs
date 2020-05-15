defmodule Mogs.Players.TrackerTest do
  use ExUnit.Case, async: true
  alias Mogs.Players.Tracker

  @test_timeout 100

  defmodule TrackBoard do
    @supervisor __MODULE__.Sup

    defstruct players: %{}
    use Mogs.Board, tracker: [timeout: 100]

    def load(_, board) do
      {:ok, struct(__MODULE__)}
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
  end

  setup_all do
    start_supervised(TrackBoard.Supervisor)
    :ok
  end

  test "a tracker can be started and monitor players with a timeout" do
    id = __ENV__.line
    player_id = 1
    assert {:ok, pid} = TrackBoard.start_server(id)

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

    for _ <- 1..10 do
      player_1 = spawn_tracked_player.(:p1)
      Process.sleep(@test_timeout)
      Process.exit(player_1, :kill)
    end

    receive do
      msg -> flunk("Received unexpected message: #{inspect(msg)}")
    after
      @test_timeout * iterations -> :ok
    end

    assert_receive({Mogs.Players.Tracker, :player_timeout, :p1})
  end
end
