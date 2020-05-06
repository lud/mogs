defmodule Mogs.BoardTest do
  use ExUnit.Case
  doctest Mogs.Board

  defmodule MyBoard do
    use Mogs.Board
    import Mogs.Board.Command.Result

    def load_mode(), do: :async

    def load(_id, info) do
      {:ok, info}
    end

    def handle_command(:dummy, board) do
      return(reply: :ok, board: board)
    end

    def handle_command(:get_the_state, board) do
      return(reply: board, board: board)
    end

    def handle_command({:stop_me, reply}, board) do
      return(reply: reply, board: board, stop: :normal)
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
    assert :ok = MyBoard.send_command(id, :dummy)
    assert :some_state = MyBoard.send_command(id, :get_the_state)
    assert true === Process.alive?(pid)
    assert :bye = MyBoard.send_command(id, {:stop_me, :bye})
    assert false === Process.alive?(pid)
  end

  defmodule ComBoard do
    use Mogs.Board

    defstruct var1: nil

    def load(_id, load_info) do
      {:ok, load_info}
    end
  end

  setup_all do
    start_supervised!(ComBoard.Supervisor)
    :ok
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
    id = :id_3
    assert {:ok, pid} = ComBoard.start_server(id: id, load_info: :some_state)

    assert nil ===
             ComBoard.send_command(id, %TransformState{
               trans: fn board -> board |> to_string |> String.upcase() end
             })

    assert "SOME_STATE" = ComBoard.read_state(id)

    assert ["SOME", "STATE"] ===
             ComBoard.send_command(id, %TransformReply{trans: &String.split(&1, "_")})

    # A command that does not return(board: ...) should keep the orginal board
    assert "SOME_STATE" = ComBoard.read_state(id)
  end
end
