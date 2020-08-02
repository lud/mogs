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

  test "adding and removing players without tracker" do
    IO.warn("todo implement players add/remove functionality without using a tracker")
  end

  test "a tracker can be started and monitor players with a timeout" do
    id = __ENV__.line

    assert {:ok, pid} =
             Mogs.Board.boot(TrackBoard, id, load_info: {:parent, self()}, tracker: [timeout: 100])

    assert pid === GenServer.whereis(TrackBoard.server_name(id))

    # Then we will start/kill the player multiple times. As long
    # as a player is re-tracked within the timeout limit, we will
    # receive no message
    iterations = 10
    wait_time = 100

    this = self()

    _player_1 = spawn_tracked_player(id, :p1)

    assert [:p1] = Mogs.Board.send_command(TrackBoard, id, :list_players)

    # This loop will add the player 2, track it, and kill it multiple times
    spawn(fn ->
      for i <- 1..10 do
        player_2 = spawn_tracked_player(id, :p2)

        if i == 1 do
          # the list is sorted by the board
          assert [:p1, :p2] = Mogs.Board.send_command(TrackBoard, id, :list_players)
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
    refute_received({:player_removed, :p2, :timeout}, "Received timeout too early")

    # now we should receive the left message
    t1 = System.monotonic_time(:millisecond)
    assert_next_receive({:player_removed, :p2, :timeout})
    t2 = System.monotonic_time(:millisecond)
    assert_in_delta t1, t2, 150, "Player timeout was too early: #{t2 - t1}"

    # Player 2 should not be in the board anymore
    assert [:p1] = Mogs.Board.send_command(TrackBoard, id, :list_players)

    # Manual remove of player 1
    Mogs.Board.remove_player(TrackBoard, id, :p1, _reason = :left)
    assert_receive({:player_removed, :p1, :left})
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

        assert :ok === Mogs.Board.track_player(TrackBoard, board_id, player_id, self)

        send(this, {:ack, ref})

        Process.sleep(:infinity)
      end)

    receive do
      {:ack, ^ref} -> pid
    end
  end
end
