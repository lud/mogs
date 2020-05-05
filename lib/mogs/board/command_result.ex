defmodule Mogs.Board.Command.Result do
  defstruct continue: true, success: true, reply: :ok, error: nil, board: nil

  @type t :: %__MODULE__{continue: boolean, success: boolean, reply: any, error: any, board: any}

  alias __MODULE__, as: M

  def return(keyword) do
    return(%__MODULE__{}, keyword)
  end

  defp return(result, []) do
    result
  end

  defp return(result, [{k, v} | keyword]) do
    return(add(result, k, v), keyword)
  end

  defp add(result, :continue, cont?) when is_boolean(cont?) do
    %M{result | continue: cont?}
  end

  defp add(result, :stop, cont?) when is_boolean(cont?) do
    %M{result | continue: not cont?}
  end

  defp add(_, k, v) when is_atom(k) do
    raise ArgumentError, "invalid return data: #{k}: #{inspect(v)}"
  end

  defp add(_, k, _) do
    raise ArgumentError, "invalid return key: #{inspect(k)}"
  end
end
