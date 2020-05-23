defmodule Mogs.BoardTest do
  use ExUnit.Case, async: true
  doctest Mogs.Board

  @db __MODULE__.DB

  # Unlike assert_receive that awaits a message matching pattern,
  # assert_next_receive will match the pattern against the first message
  # received. Used to check order of messages
  defmacro assert_next_receive(pattern, timeout \\ 1000) do
    quote do
      receive do
        message ->
          assert unquote(pattern) = message
      after
        unquote(timeout) ->
          raise "timeout"
      end
    end
  end

  defmodule MyBoard do
    use Mogs.Board, load_mode: :async
    import Mogs.Board.Command.Result

    require TestHelpers.NoWarnings
    TestHelpers.NoWarnings.fake_fun(:handle_add_player, 3)
    TestHelpers.NoWarnings.fake_fun(:handle_remove_player, 3)

    def load(_id, info) do
      {:ok, info}
    end

    def handle_command(:dummy, board) do
      cast_return(reply: :ok, board: board)
    end

    def handle_command(:get_the_state, board) do
      cast_return(reply: board, board: board)
    end

    def handle_command({:stop_me, reply}, _board) do
      cast_return(reply: reply, board: :GOT_TO_STOP)
    end

    def handle_update(:GOT_TO_STOP) do
      {:stop, :normal}
    end

    def handle_update(board) do
      {:ok, board}
    end
  end

  test "can start/stop a board server with supervision & registry" do
    assert true = is_pid(Process.whereis(MyBoard.Supervisor))
    assert true = is_pid(Process.whereis(MyBoard.Server.Registry))
    assert true = is_pid(Process.whereis(MyBoard.Server.DynamicSupervisor))
    id = __ENV__.line
    assert {:ok, pid} = MyBoard.start_server(id)
    pid = Registry.whereis_name({MyBoard.Server.Registry, id})
    assert true = is_pid(pid)
    assert true = Process.alive?(pid)

    # stopping
    assert :ok = MyBoard.stop_server(id)
    assert :undefined = Registry.whereis_name({MyBoard.Server.Registry, id})
    assert false === Process.alive?(pid)
  end

  test "can read the state of a board" do
    assert {:ok, pid} = MyBoard.start_server(:id_1, load_info: "hello")
    assert "HELLO" = MyBoard.read_state(:id_1, &String.upcase/1)
  end

  test "can handle a tuple command" do
    id = :id_2
    assert {:ok, pid} = MyBoard.start_server(id, load_info: :some_state_tup)
    assert :ok = MyBoard.send_command(id, :dummy)
    assert :some_state_tup = MyBoard.send_command(id, :get_the_state)
    assert true === Process.alive?(pid)
    assert :bye = MyBoard.send_command(id, {:stop_me, :bye})
    Process.sleep(100)
    assert false === Process.alive?(pid)
  end

  defmodule ComBoard do
    use Mogs.Board

    require TestHelpers.NoWarnings
    TestHelpers.NoWarnings.fake_fun(:handle_add_player, 3)
    TestHelpers.NoWarnings.fake_fun(:handle_remove_player, 3)
    TestHelpers.NoWarnings.handle_update()

    defstruct var1: nil

    def load(_id, load_info) do
      {:ok, load_info}
    end
  end

  defmodule TransformState do
    use Mogs.Board.Command
    defstruct trans: nil

    def run(%{trans: fun}, board) do
      return(board: fun.(board))
    end
  end

  defmodule TransformReply do
    use Mogs.Board.Command
    defstruct trans: nil

    def run(%{trans: fun}, board) do
      return(reply: fun.(board))
    end
  end

  test "can handle a struct command" do
    id = __ENV__.line
    assert {:ok, pid} = ComBoard.start_server(id, load_info: :some_state_atom)

    assert :ok ===
             ComBoard.send_command(id, %TransformState{
               trans: fn board -> board |> to_string |> String.upcase() end
             })

    assert "SOME_STATE_ATOM" = ComBoard.read_state(id)

    assert ["SOME", "STATE", "ATOM"] ===
             ComBoard.send_command(id, %TransformReply{trans: &String.split(&1, "_")})

    # A command that does not return(board: ...) should keep the orginal board
    assert "SOME_STATE_ATOM" = ComBoard.read_state(id)
  end

  defmodule TimedBoard do
    use Mogs.Board
    require Logger
    @db Mogs.BoardTest.DB

    require TestHelpers.NoWarnings
    TestHelpers.NoWarnings.fake_fun(:handle_add_player, 3)
    TestHelpers.NoWarnings.fake_fun(:handle_remove_player, 3)

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

      return(board: board)
    end

    def handle_timer({pid, name}, board) do
      IO.puts("send #{inspect({:handled!, name})}")
      send(pid, {:handled!, name})
      return(board: board)
    end
  end

  test "a command can set a timer and handle it" do
    id = __ENV__.line
    assert {:ok, pid} = TimedBoard.start_server(id, load_info: :some_state_timers, timers: true)
    assert pid === GenServer.whereis(TimedBoard.__name__(id))

    TimedBoard.send_command(id, %SetTimer{test_pid: self()})

    # Process.sleep(2000)
    :erlang.process_info(self(), :messages) |> IO.inspect()

    # raise "fuck"
    assert_next_receive({:handled!, :timer_1}, 400)
    assert_next_receive({:handled!, :timer_2}, 400)
    assert_next_receive({:handled!, :timer_3}, 400)

    TimedBoard.read_state(id, fn board ->
      assert 0 = TimeQueue.size(board.timers)
    end)

    # sync_cub()
  end

  test "a board can stop and restart and still handle timers" do
    id = __ENV__.line
    assert {:ok, pid} = TimedBoard.start_server(id, load_info: :some_state_timers_2, timers: true)
    TimedBoard.send_command(id, %SetTimer{test_pid: self()})
    pid = GenServer.whereis(TimedBoard.__name__(id))
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

    start_supervised!(ComBoard.Supervisor)
    start_supervised!(MyBoard.Supervisor)
    start_supervised!(TimedBoard.Supervisor)
    {:ok, _} = CubDB.start_link(db_dir, name: @db)

    :ok
  end

  defmodule AnomBoard do
    use Mogs.Board, load_mode: :async, registry: false, server_sup: false, supervisor: false

    require TestHelpers.NoWarnings
    TestHelpers.NoWarnings.__name__()
    TestHelpers.NoWarnings.fake_fun(:handle_add_player, 3)
    TestHelpers.NoWarnings.fake_fun(:handle_remove_player, 3)
    TestHelpers.NoWarnings.handle_update()

    def load(_id, load_info) do
      {:ok, load_info}
    end
  end

  test "can start/stop anonymous, unsupervised boards" do
    id = __ENV__.line

    assert_raise UndefinedFunctionError, fn ->
      AnomBoard.start_server(id)
    end

    assert nil === AnomBoard.__name__(id)

    assert {:ok, pid} =
             Mogs.Board.Server.start_link(
               id: id,
               mod: AnomBoard,
               name: nil,
               load_info: :some_state_anon
             )

    assert pid === AnomBoard.__name__(pid)

    assert true = is_pid(pid)
    assert true = Process.alive?(pid)

    # We can still use the functions created in AnomBoard with a pid
    assert :some_state_anon = AnomBoard.read_state(pid)

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
