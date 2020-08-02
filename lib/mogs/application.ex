defmodule Mogs.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, name: Mogs.Board.Registry, keys: :unique},
      {DynamicSupervisor, strategy: :one_for_one, name: Mogs.Board.DynamicSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mogs.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
