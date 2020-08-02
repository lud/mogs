defmodule Mogs.BoardTest do
  use ExUnit.Case, async: true
  doctest Mogs.Board

  @db __MODULE__.DB

  import Mogs.TestHelper

  defmodule MyBoard do
    use Mogs.Board
    Mogs.TestHelper.suppress_callback_warnings()
    import Mogs.Board.Command.Result

    def load(_id, info) do
      {:ok, info}
    end

    def handle_command(:dummy, board) do
      cast_result(reply: :ok, board: board)
    end

    def handle_command(:get_the_state, board) do
      cast_result(reply: board, board: board)
    end

    def handle_command({:stop_me, reply}, _board) do
      cast_result(reply: reply, board: :GOT_TO_STOP)
    end

    def handle_update(:GOT_TO_STOP) do
      {:stop, :normal}
    end

    def handle_update(board) do
      {:ok, board}
    end
  end

  test "can start/stop a board server with supervision & registry" do
    id = __ENV__.line
    assert {:ok, pid} = Mogs.Board.boot(MyBoard, id)
    pid = Registry.whereis_name({Mogs.Board.Registry, id})
    assert true = is_pid(pid)
    assert true = Process.alive?(pid)

    # stopping
    assert :ok = Mogs.Board.stop(MyBoard, id)
    assert :undefined = Registry.whereis_name({Mogs.Board.Registry, id})
    assert false === Process.alive?(pid)
  end

  test "can read the state of a board" do
    assert {:ok, pid} = Mogs.Board.boot(MyBoard, :id_1, load_info: "hello")
    assert "HELLO" = Mogs.Board.read_state(MyBoard, :id_1, &String.upcase/1)
  end

  test "can handle a tuple command" do
    id = :id_2
    assert {:ok, pid} = Mogs.Board.boot(MyBoard, id, load_info: :some_state_tup)
    assert :ok = Mogs.Board.send_command(MyBoard, id, :dummy)
    assert :some_state_tup = Mogs.Board.send_command(MyBoard, id, :get_the_state)
    assert true === Process.alive?(pid)
    assert :bye = Mogs.Board.send_command(MyBoard, id, {:stop_me, :bye})
    Process.sleep(100)
    assert false === Process.alive?(pid)
  end

  defmodule ComBoard do
    use Mogs.Board
    Mogs.TestHelper.suppress_callback_warnings()
    defstruct var1: nil

    def load(_id, load_info) do
      {:ok, load_info}
    end

    def handle_update(board) do
      {:ok, board}
    end
  end

  defmodule TransformState do
    use Mogs.Board.Command
    defstruct trans: nil

    def run(%{trans: fun}, board) do
      result(board: fun.(board))
    end
  end

  defmodule TransformReply do
    use Mogs.Board.Command
    defstruct trans: nil

    def run(%{trans: fun}, board) do
      result(reply: fun.(board))
    end
  end

  test "can handle a struct command" do
    id = __ENV__.line
    assert {:ok, pid} = Mogs.Board.boot(ComBoard, id, load_info: :some_state_atom)

    assert :ok ===
             Mogs.Board.send_command(ComBoard, id, %TransformState{
               trans: fn board -> board |> to_string |> String.upcase() end
             })

    assert "SOME_STATE_ATOM" = Mogs.Board.get_state(ComBoard, id)

    assert ["SOME", "STATE", "ATOM"] ===
             Mogs.Board.send_command(ComBoard, id, %TransformReply{trans: &String.split(&1, "_")})

    # A command that does not result(board: ...) should keep the orginal board
    assert "SOME_STATE_ATOM" = Mogs.Board.get_state(ComBoard, id)
  end

  defmodule TimedBoard do
    use Mogs.Board
    Mogs.TestHelper.suppress_callback_warnings()
    require Logger
    @db Mogs.BoardTest.DB

    @derive {Mogs.Timers.Store, :timers}
    defstruct id: nil, timers: Mogs.Timers.new()

    def load(id, _load_info) do
      case CubDB.fetch(@db, {__MODULE__, id}) do
        {:ok, board} -> {:ok, board}
        :error -> {:ok, %__MODULE__{id: id}}
      end
    end

    def handle_update(%{id: id} = board) do
      CubDB.put(@db, {__MODULE__, id}, board)

      {:ok, board}
    end
  end

  defmodule SetTimer do
    use Mogs.Board.Command
    defstruct test_pid: nil

    def run(%{test_pid: pid}, board) do
      # reverse ttl order
      board = start_timer(board, {300, :ms}, {pid, :timer_3})
      board = start_timer(board, {200, :ms}, {pid, :timer_2})
      board = start_timer(board, {100, :ms}, {pid, :timer_1})

      result(board: board)
    end

    def handle_timer({pid, name}, board) do
      send(pid, {:handled!, name})
      result(board: board)
    end
  end

  test "a command can set a timer and handle it" do
    id = __ENV__.line

    assert {:ok, pid} =
             Mogs.Board.boot(TimedBoard, id, load_info: :some_state_timers, timers: true)

    assert pid === GenServer.whereis(TimedBoard.server_name(id))

    Mogs.Board.send_command(TimedBoard, id, %SetTimer{test_pid: self()})

    assert_next_receive({:handled!, :timer_1}, 400)
    assert_next_receive({:handled!, :timer_2}, 400)
    assert_next_receive({:handled!, :timer_3}, 400)

    Mogs.Board.read_state(TimedBoard, id, fn board ->
      assert 0 = TimeQueue.size(board.timers)
    end)

    # sync_cub()
  end

  test "a board can stop and restart and still handle timers" do
    id = __ENV__.line

    assert {:ok, pid} =
             Mogs.Board.boot(TimedBoard, id, load_info: :some_state_timers_2, timers: true)

    Mogs.Board.send_command(TimedBoard, id, %SetTimer{test_pid: self()})
    pid = GenServer.whereis(TimedBoard.server_name(id))
    # We will kill the board, and still expect to receive our timers,
    # as the timers data (our pid) must be stored in the state.
    # But that works only because the board has a persistence storage.
    Process.exit(pid, :kill)

    # After beeing restated by the supervisor and loading the
    # persisted state, we expect the server to run a lifecyle loop and
    # call our timers
    assert_receive({:handled!, :timer_1}, 400)
    assert_receive({:handled!, :timer_2}, 400)
    assert_receive({:handled!, :timer_3}, 400)

    # sync_cub()
  end

  setup_all do
    db_dir = "test/db/#{__MODULE__}"

    case File.rm_rf(db_dir) do
      {:ok, _} -> :ok
      {:error, :enoent} -> :ok
      other -> raise "Could not cleanup test db: #{inspect(other)}"
    end

    {:ok, _} = CubDB.start_link(db_dir, name: @db)

    :ok
  end

  defmodule AnomBoard do
    use Mogs.Board
    Mogs.TestHelper.suppress_callback_warnings()

    def server_name(pid) when is_pid(pid), do: pid
    def server_name(_), do: nil

    def load(_id, load_info) do
      {:ok, load_info}
    end
  end

  test "can start/stop anonymous, unsupervised boards" do
    id = __ENV__.line

    assert nil === AnomBoard.server_name(id)

    assert {:ok, pid} =
             Mogs.Board.Server.start_link(
               id: id,
               module: AnomBoard,
               name: nil,
               load_info: :some_state_anon
             )

    assert Process.alive?(pid)

    assert pid === AnomBoard.server_name(pid)

    assert true = is_pid(pid)
    assert true = Process.alive?(pid)

    # We can still use the functions created in AnomBoard with a pid
    assert :some_state_anon = Mogs.Board.get_state(AnomBoard, pid)

    assert :ok = GenServer.stop(pid)
    assert false === Process.alive?(pid)
  end

  # defp sync_cub() do
  #   Task.await(
  #     Task.async(fn ->
  #       CubDB.subscribe(@db)
  #       CubDB.compact(@db)
  #       assert_receive :compaction_completed
  #       assert_receive :catch_up_completed
  #     end)
  #   )
  # end
end
