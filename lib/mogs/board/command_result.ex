defmodule Mogs.Board.Command.Result do
  @todo "Convert to a tuple if we do not need to stop a board from a command"

  defstruct ok?: true,
            reply: nil,
            board: nil,
            reason: nil

  @type t :: %__MODULE__{
          ok?: boolean,
          reply: any,
          board: any,
          reason: any
        }

  alias __MODULE__, as: M

  @accepted_keys ~w(reply error board)a

  def return(keyword) do
    return(%__MODULE__{}, keyword)
  end

  def return(result, return_info)

  def return(result, []) do
    result
  end

  def return(result, [{k, v} | keyword]) do
    return(add(result, k, v), keyword)
  end

  defp add(result, :board, board) do
    %M{result | board: board}
  end

  defp add(result, :reply, reply) do
    %M{result | reply: reply}
  end

  defp add(result, :error, reason) do
    put_default_reply(%M{result | ok?: false, reason: reason}, {:error, reason})
  end

  defp add(_, k, v) when k in @accepted_keys do
    raise ArgumentError, "invalid result value for #{k}: #{inspect(v)}"
  end

  defp add(_, k, _) do
    raise ArgumentError, "invalid result key: #{inspect(k)}"
  end

  defp put_default_reply(%M{reply: nil} = result, reply) do
    %M{result | reply: reply}
  end

  defp put_default_reply(%M{} = result, _reply) do
    result
  end

  def put_default_board(%M{board: nil} = result, board) do
    %M{result | board: board}
  end

  def put_default_board(%M{} = result, _board) do
    result
  end
end
