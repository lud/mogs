defmodule Mogs.Board.Command.Result do
  use TODO
  @todo "Convert to a tuple if we do not need to stop a board from a command"

  defstruct ok?: true,
            reply: :ok,
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
    reply =
      case result.reply do
        nil -> {:error, reason}
        :ok -> {:error, reason}
        other -> other
      end

    %M{result | ok?: false, reason: reason, reply: reply}
  end

  defp add(_, k, v) when k in @accepted_keys do
    raise ArgumentError, "invalid result value for #{k}: #{inspect(v)}"
  end

  defp add(_, k, _) do
    raise ArgumentError, "invalid result key: #{inspect(k)}"
  end

  def put_default_board(%M{board: nil} = result, board) do
    %M{result | board: board}
  end

  def put_default_board(%M{} = result, _board) do
    result
  end
end
