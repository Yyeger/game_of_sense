defmodule LifeSemantic.Cache do
  @moduledoc """
  ETS cache: (current_concept, sorted_neighbors) -> new_concept.

  Many different physical positions map to the same "semantic neighborhood",
  so this collapses the inference count dramatically once the board stabilizes.
  """
  use GenServer

  @table :life_semantic_cache

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def get(current, neighbors) do
    key = make_key(current, neighbors)

    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:hit, value}
      [] -> :miss
    end
  end

  def put(current, neighbors, value) do
    key = make_key(current, neighbors)
    :ets.insert(@table, {key, value})
    value
  end

  def stats do
    size = :ets.info(@table, :size)
    %{entries: size}
  end

  defp make_key(current, neighbors) do
    {current || :empty, neighbors |> Enum.map(&(&1 || :empty)) |> Enum.sort()}
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end
end
