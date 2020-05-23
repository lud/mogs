defmodule Mogs.Board.Command.Result do
  use TODO
  @todo "Convert to a tuple if we do not need to stop a board from a command"

  defstruct ok?: true,
            stop: false,
            # no defaults:
            reply: nil,
            board: nil,
            reason: nil

  @type t :: %__MODULE__{
          ok?: boolean,
          reply: any,
          board: any,
          reason: any,
          stop: false | {true, reason :: any}
        }

  @type overrides_kw :: Keyword.t()

  @type overrides :: %{
          :__partial__ => true,
          optional(:board) => any,
          optional(:stop) => boolean,
          optional(:reply) => any,
          optional(:ok?) => boolean
        }

  alias __MODULE__, as: M

  @accepted_keys ~w(reply error board stop)a
  @todo "Enable from_tuple/1 ?"
  @todo "Enable cast/1 ?"

  def merge(defaults, overrides) do
    ret_defaults = return(defaults)
    ret_overrides = return(overrides)
    merged = Map.merge(ret_defaults, ret_overrides)
    struct(M, merged)
  end

  def with_defaults(overrides, defaults) do
    merge(defaults, overrides)
  end

  def return(%{__partial__: true} = map) do
    map
  end

  def return(keyword) when is_list(keyword) do
    cast_kw(%{__partial__: true}, keyword)
  end

  def return(tuple) when is_tuple(tuple) do
    cast_tuple(tuple)
  end

  def return(other) do
    raise_bad_return(other)
  end

  def cast_return(overrides) do
    merge(%{__partial__: true}, overrides)
  end

  defp raise_bad_return(other) do
    raise ArgumentError, """
    The command did not return a valid result.

    The return/1 function accepts only keywords, specific tuples, or
    result partials. Generally you will use it with a keyword such as:

        return(board: board, reply: :ok)

    The following data was passed:

        #{inspect(other, pretty: true)}
    """
  end

  def return_board(board, keyword \\ []) do
    return([{:board, board} | keyword])
  end

  defp cast_kw(map, [{k, v} | keyword]) do
    cast_kw(add(map, k, v), keyword)
  end

  defp cast_kw(map, []) do
    map
  end

  defp add(map, :board, board) do
    Map.put(map, :board, board)
  end

  defp add(map, :reply, reply) do
    Map.put(map, :reply, reply)
  end

  defp add(map, :error, reason) do
    map
    |> Map.merge(%{reason: reason, ok?: false})
    |> Map.put_new(:reply, {:error, reason})
  end

  defp add(map, :stop, true) do
    add(map, :stop, :normal)
  end

  defp add(map, :stop, false) do
    Map.delete(map, :stop)
  end

  defp add(map, :stop, reason) do
    Map.put(map, :stop, {true, reason})
  end

  defp add(_, k, v) when k in @accepted_keys do
    raise ArgumentError, "invalid result value for #{k}: #{inspect(v)}"
  end

  defp add(_, k, _) do
    raise ArgumentError, "invalid result key: #{inspect(k)}"
  end

  defp cast_tuple({:ok, board}) do
    %{board: board}
  end

  defp cast_tuple({:error, reason} = err) do
    %{ok?: false, reason: reason, reply: err}
  end

  defp cast_tuple({:stop, reason} = err) do
    %{stop: {true, reason}}
  end

  defp cast_tuple(other) do
    raise_bad_return(other)
  end
end
