defmodule Mogs.Players.TrackerTest do
  use ExUnit.Case, async: true
  import Mogs.TestHelper
  @test_timeout 100

  defmodule TrackBoard do
    use Mogs.Board
    defstruct players: %{}, test_process_pid: nil
    require Logger

    def load(_, {:parent, pid} = _load_info) when is_pid(pid) do
      {:ok, struct(__MODULE__, test_process_pid: pid)}
    end

    def handle_add_player(board, player_id, data) do
      case Map.get(board.players, player_id) do
        nil -> {:ok, put_in(board.players[player_id], data)}
        _ -> {:error, :already_in}
      end
    end

    def handle_remove_player(board, player_id, reason) do
      %__MODULE__{test_process_pid: pid} = board
      send(pid, {:player_removed, player_id, reason})
      players = Map.delete(board.players, player_id)

      case map_size(players) do
        0 -> {:stop, :normal}
        _ -> {:ok, %{board | players: players}}
      end
    end

    def handle_command(:list_players, board) do
      list = Map.keys(board.players) |> Enum.sort()
      Mogs.Board.Command.Result.merge([], board: board, reply: list)
    end

    def handle_update(board) do
      {:ok, board}
    end

    def handle_error(error, board) do
      IO.puts([IO.ANSI.red(), inspect(error), IO.ANSI.default_color()])
      {:ok, board}
    end
  end

  test "a tracker can be started and monitor players with a timeout" do
    id = __ENV__.line

    assert {:ok, pid} =
             Mogs.Board.boot(TrackBoard, id,
               load_info: {:parent, self()},
               tracker: [timeout: @test_timeout]
             )

    assert pid === GenServer.whereis(TrackBoard.server_name(id))

    _player_1 = spawn_tracked_player(id, :p1)

    assert [:p1] = Mogs.Board.send_command(TrackBoard, id, :list_players)

    player_2 = spawn_tracked_player(id, :p2)
    assert [:p1, :p2] = Mogs.Board.send_command(TrackBoard, id, :list_players)

    t1 = System.monotonic_time(:millisecond)
    Process.exit(player_2, :kill)
    Process.sleep(@test_timeout - 10)
    refute_received({:player_removed, :p2, :timeout}, "Received timeout too early")
    assert_next_receive({:player_removed, :p2, :timeout})
    t2 = System.monotonic_time(:millisecond)
    assert_in_delta t1, t2, 105, "Player timeout was too early: #{t2 - t1}"
    assert t2 - t1 > @test_timeout

    # Player 2 should not be in the board anymore
    assert [:p1] = Mogs.Board.send_command(TrackBoard, id, :list_players)

    # Manual remove of player 1
    Mogs.Board.remove_player(TrackBoard, id, :p1, _reason = :left)
    assert_receive({:player_removed, :p1, :left})
    Process.sleep(1000)
    refute Mogs.Board.alive?(TrackBoard, id)
  end

  # Adds a player to the board and waits until the player is tracked by the
  # board before returning
  defp spawn_tracked_player(board_id, player_id) do
    ref = make_ref()
    this = self()

    pid =
      spawn(fn ->
        case Mogs.Board.add_player(TrackBoard, board_id, player_id, :some_data) do
          :ok -> :ok
          {:error, :already_in} -> :ok
        end

        assert :ok === Mogs.Board.track_player(TrackBoard, board_id, player_id, self())

        send(this, {:ack, ref})

        Process.sleep(:infinity)
      end)

    receive do
      {:ack, ^ref} -> pid
    end
  end

  defmodule NoTrackBoard do
    use Mogs.Board
    defstruct players: %{}, test_process_pid: nil
    require Logger

    def load(_, {:parent, pid} = _load_info) when is_pid(pid) do
      {:ok, struct(__MODULE__, test_process_pid: pid)}
    end

    def handle_add_player(board, player_id, data) do
      case Map.get(board.players, player_id) do
        nil -> {:ok, put_in(board.players[player_id], data)}
        _ -> {:error, :already_in}
      end
    end

    def handle_remove_player(board, player_id, reason) do
      %__MODULE__{test_process_pid: pid} = board
      send(pid, {:player_removed, player_id, reason})
      players = Map.delete(board.players, player_id)

      case map_size(players) do
        0 -> {:stop, :normal}
        _ -> {:ok, %{board | players: players}}
      end
    end

    def handle_command(:list_players, board) do
      list = Map.keys(board.players) |> Enum.sort()
      Mogs.Board.Command.Result.merge([], board: board, reply: list)
    end

    def handle_update(board) do
      {:ok, board}
    end

    def handle_error(error, board) do
      IO.puts([IO.ANSI.red(), inspect(error), IO.ANSI.default_color()])
      {:ok, board}
    end
  end

  test "adding and removing players without tracker" do
    id = __ENV__.line

    assert {:ok, pid} = Mogs.Board.boot(TrackBoard, id, load_info: {:parent, self()})
    assert :ok = Mogs.Board.add_player(TrackBoard, id, :p1, nil)
    assert [:p1] = Mogs.Board.send_command(TrackBoard, id, :list_players)
    assert :ok = Mogs.Board.add_player(TrackBoard, id, :p2, nil)
    assert [:p1, :p2] = Mogs.Board.send_command(TrackBoard, id, :list_players)

    # Process.sleep(1000)

    # refute_receive(
    #   {:player_removed, :p2, :timeout},
    #   1000,
    #   "Should not have received player timeout since tracker is disabled"
    # )

    # Mogs.Board.remove_player(TrackBoard, id, :p2, :left)
    # assert_next_receive({:player_removed, :p2, :left})

    # # Player 2 should not be in the board anymore
    # assert [:p1] = Mogs.Board.send_command(TrackBoard, id, :list_players)

    # # Manual remove of player 1
    # Mogs.Board.remove_player(TrackBoard, id, :p1, _reason = :left)
    # assert_receive({:player_removed, :p1, :left})
    # refute Mogs.Board.alive?(TrackBoard, id)
  end
end
