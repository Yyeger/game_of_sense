defmodule LifeSemantic.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LifeSemantic.Cache,
      {LifeSemantic.Grid, size: 20}
    ]

    opts = [strategy: :one_for_one, name: LifeSemantic.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
