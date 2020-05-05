defmodule MogsTest do
  use ExUnit.Case
  doctest Mogs

  defmodule MyBoard do
    use Mogs.Board

    def load_mode(), do: :async

    def load(_id, info) do
      {:ok, info}
    end

    def run_command(:dummy, board) do
      {:ok, board}
    end

    def run_command(:get_the_state, board) do
      {:ok, board, board}
    end

    def run_command({:stop_me, reply}, _board) do
      {:stop, :normal, reply}
    end
  end

  setup_all do
    start_supervised!(MyBoard.Supervisor)
    :ok
  end

  test "can start/stop a board server with supervision & registry" do
    assert true = is_pid(Process.whereis(MyBoard.Supervisor))
    assert true = is_pid(Process.whereis(MyBoard.Server.Registry))
    assert true = is_pid(Process.whereis(MyBoard.Server.DynamicSupervisor))
    id = {:some, :id}
    assert {:ok, pid} = MyBoard.start_server(id: id)
    pid = Registry.whereis_name({MyBoard.Server.Registry, id})
    assert true = is_pid(pid)
    assert true = Process.alive?(pid)

    # stopping
    assert :ok = MyBoard.stop_server(id)
    assert :undefined = Registry.whereis_name({MyBoard.Server.Registry, id})
    assert false === Process.alive?(pid)
  end

  test "can read the state of a board" do
    assert {:ok, pid} = MyBoard.start_server(id: :id_1, load_info: "hello")
    assert "HELLO" = MyBoard.read_state(:id_1, &String.upcase/1)
  end

  test "can handle a tuple command" do
    id = :id_2
    assert {:ok, pid} = MyBoard.start_server(id: id, load_info: :some_state)
    assert :ok = MyBoard.send_command(id, {MyBoard, :dummy})
    assert :some_state = MyBoard.send_command(id, {MyBoard, :get_the_state})
    assert true === Process.alive?(pid)
    assert :bye = MyBoard.send_command(id, {MyBoard, {:stop_me, :bye}})
    assert false === Process.alive?(pid)
  end

  defmodule ComBoard do
    use Mogs.Board
    @behaviour Mogs.Board.Command

    defstruct var1: nil
  end

  setup_all do
    start_supervised!(ComBoard.Supervisor)
    :ok
  end

  defmodule Com1 do
  end

  test "can handle a struct command" do
    id = :id_3
    assert {:ok, pid} = ComBoard.start_server(id: id, load_info: :some_state)
    assert "SOME_STATE" = ComBoard.send_command(id, %ComBoard{})
  end
end
