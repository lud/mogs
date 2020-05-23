defmodule Mogs.Players.TrackerTest do
  use ExUnit.Case, async: true
  alias Mogs.Players.Tracker

  @test_timeout 100

  defmodule TrackBoard do
    defstruct players: %{}, test_process_pid: nil
    require Logger
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

    def handle_remove_player(board, player_id, reason) do
      %__MODULE__{test_process_pid: pid} = board
      send(pid, {:player_removed, player_id, reason})
      players = Map.delete(board.players, player_id)

      Logger.warn("Removing player #{player_id}")

      case map_size(players) do
        0 ->
          Logger.warn("No more players in #{__MODULE__}, stopping")
          {:stop, :normal}

        _ ->
          {:ok, %{board | players: players}}
      end
    end

    def handle_command(:list_players, board) do
      IO.inspect(board, label: "BOARD")
      list = Map.keys(board.players) |> Enum.sort()
      Mogs.Board.Command.Result.merge([], board: board, reply: list)
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

    assert pid === GenServer.whereis(TrackBoard.__name__(id))

    # Then we will start/kill the player multiple times. As long
    # as a player is re-tracked within the timeout limit, we will
    # receive no message
    iterations = 10
    wait_time = 100

    this = self()

    player_1 = spawn_tracked_player(id, :p1)

    assert [:p1] = TrackBoard.send_command(id, :list_players)

    spawn(fn ->
      for i <- 1..10 do
        player_2 = spawn_tracked_player(id, :p2)

        if i == 1 do
          # the list is sorted by the board
          assert [:p1, :p2] = TrackBoard.send_command(id, :list_players)
        end

        Process.sleep(wait_time)
        Process.exit(player_2, :kill)
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
    refute_received({:player_removed, :p2, :timeout}, "Received timeout too early")
    assert_receive({:player_removed, :p2, :timeout}, @test_timeout + 50)

    # Player 2 should not be in the board anymore
    assert [:p1] = TrackBoard.send_command(id, :list_players)

    # Manual remove of player 1
    TrackBoard.remove_player(id, :p1, _reason = :left)
    assert_receive({:player_removed, :p1, :left})
    refute TrackBoard.alive?(id)
  end

  defp spawn_tracked_player(board_id, player_id) do
    ref = make_ref()
    this = self()

    pid =
      spawn(fn ->
        case TrackBoard.add_player(board_id, player_id, :some_data) do
          :ok -> :ok
          {:error, :already_in} -> TrackBoard.track_player(board_id, player_id)
        end

        send(this, {:ack, ref})

        Process.sleep(:infinity)
      end)

    receive do
      {:ack, ^ref} -> pid
    end
  end
end
