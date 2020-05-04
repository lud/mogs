defmodule MogsTest do
  use ExUnit.Case
  doctest Mogs

  defmodule MyBoard do
    use Mogs.Board
    @behaviour Mogs.Board

    def load_mode(), do: :async

    def load(_id, info) do
      {:ok, info}
    end
  end

  setup_all do
    start_supervised!(MyBoard.Supervisor)
    :ok
  end

  test "can create a board module with supervision" do
    assert true = is_pid(Process.whereis(MyBoard.Supervisor))
    assert true = is_pid(Process.whereis(MyBoard.Server.Registry))
    assert true = is_pid(Process.whereis(MyBoard.Server.DynamicSupervisor))
    id = {:some, :id}
    assert {:ok, pid} = MyBoard.start_server(id: id)
    assert true = is_pid(Registry.whereis_name({MyBoard.Server.Registry, id}))
    assert true = Process.alive?(Registry.whereis_name({MyBoard.Server.Registry, id}))
  end

  test "can read the state of a board" do
    assert {:ok, pid} = MyBoard.start_server(id: :id_1, load_info: "hello")
    assert "HELLO" = MyBoard.read_state(:id_1, &String.upcase/1)
  end
end
