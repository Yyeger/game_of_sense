defmodule LifeSemantic.Grid do
  @moduledoc """
  Holds the NxN grid of concepts and advances it one generation at a time.

  Grid is a map `%{{x, y} => concept_string | nil}` where nil means empty.
  Toroidal wrap-around so the edges behave.
  """
  use GenServer

  alias LifeSemantic.{Cache, Ollama}

  @seed ~w(water fire dirt sun air stone plant wood metal wind ice seed
           salt smoke dust moss spark cloud root blood bone light shadow)

  # Spawn this many random seeds into empty cells each tick, so the board
  # doesn't collapse to a handful of attractor concepts.
  @spawn_per_tick 4

  # ---- Public API ----

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def size, do: GenServer.call(__MODULE__, :size)
  def generation, do: GenServer.call(__MODULE__, :generation)
  def tick, do: GenServer.call(__MODULE__, :tick, :infinity)
  def reseed, do: GenServer.call(__MODULE__, :reseed)

  # ---- GenServer ----

  @impl true
  def init(opts) do
    size = Keyword.get(opts, :size, 20)

    {:ok,
     %{
       size: size,
       grid: seed_grid(size),
       generation: 0,
       last_changed: 0,
       last_spawned: 0
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.grid, state}
  def handle_call(:size, _from, state), do: {:reply, state.size, state}

  def handle_call(:generation, _from, state),
    do: {:reply, {state.generation, state.last_changed, state.last_spawned}, state}

  def handle_call(:reseed, _from, state) do
    {:reply, :ok,
     %{state | grid: seed_grid(state.size), generation: 0, last_changed: 0, last_spawned: 0}}
  end

  def handle_call(:tick, _from, state) do
    {transitioned, changed} = advance(state.grid, state.size)
    {new_grid, spawned} = spawn_new(transitioned, state.size, @spawn_per_tick)

    {:reply, {changed, spawned},
     %{
       state
       | grid: new_grid,
         generation: state.generation + 1,
         last_changed: changed,
         last_spawned: spawned
     }}
  end

  # ---- Seeding ----

  defp seed_grid(size) do
    empty =
      for x <- 0..(size - 1), y <- 0..(size - 1), into: %{} do
        {{x, y}, nil}
      end

    # Seed ~8% of cells with random basic concepts
    cells_to_seed = div(size * size, 12)

    Enum.reduce(1..cells_to_seed, empty, fn _, acc ->
      x = :rand.uniform(size) - 1
      y = :rand.uniform(size) - 1
      concept = Enum.random(@seed)
      Map.put(acc, {x, y}, concept)
    end)
  end

  # ---- Generation step ----

  defp advance(grid, size) do
    cells = for x <- 0..(size - 1), y <- 0..(size - 1), do: {x, y}

    # Only compute transitions for cells that have neighbors OR are non-empty.
    # Empty cells with 0 neighbors stay empty without consulting the LLM.
    updates =
      cells
      |> Enum.map(fn pos ->
        {pos, Map.get(grid, pos), neighbors_of(grid, pos, size)}
      end)
      |> Enum.filter(fn {_pos, cur, neighbors} ->
        non_empty = Enum.count(neighbors, & &1)
        cur != nil or non_empty >= 3
      end)
      |> Task.async_stream(
        fn {pos, cur, neighbors} -> {pos, resolve(cur, neighbors)} end,
        max_concurrency: 6,
        timeout: 60_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, v} -> v end)

    new_grid =
      Enum.reduce(updates, grid, fn {pos, new_val}, acc ->
        Map.put(acc, pos, new_val)
      end)

    changed =
      Enum.count(updates, fn {pos, new_val} -> Map.get(grid, pos) != new_val end)

    {new_grid, changed}
  end

  defp resolve(current, neighbors) do
    # Rule short-circuits before calling the LLM:
    non_empty_count = Enum.count(neighbors, & &1)

    cond do
      # Lonely non-empty cell with 0 neighbors -> dies (classic GoL feel)
      current != nil and non_empty_count == 0 ->
        nil

      # Empty cell with few neighbors -> stays empty
      current == nil and non_empty_count < 3 ->
        nil

      true ->
        case Cache.get(current, neighbors) do
          {:hit, v} ->
            v

          :miss ->
            case Ollama.transition(current, neighbors) do
              {:ok, v} -> Cache.put(current, neighbors, v)
              {:error, _} -> current
            end
        end
    end
  end

  # Inject up to N random seeds into currently-empty cells. Prevents the
  # board from degenerating into a few dominant attractor concepts.
  defp spawn_new(grid, _size, 0), do: {grid, 0}

  defp spawn_new(grid, _size, count) do
    empty_positions =
      grid
      |> Enum.filter(fn {_pos, v} -> is_nil(v) end)
      |> Enum.map(fn {pos, _} -> pos end)

    spawn_count = min(count, length(empty_positions))

    picks = empty_positions |> Enum.shuffle() |> Enum.take(spawn_count)

    new_grid =
      Enum.reduce(picks, grid, fn pos, acc ->
        Map.put(acc, pos, Enum.random(@seed))
      end)

    {new_grid, spawn_count}
  end

  defp neighbors_of(grid, {x, y}, size) do
    # Moore neighborhood, row-major order: NW N NE W E SW S SE
    for dy <- [-1, 0, 1], dx <- [-1, 0, 1], {dx, dy} != {0, 0} do
      nx = Integer.mod(x + dx, size)
      ny = Integer.mod(y + dy, size)
      Map.get(grid, {nx, ny})
    end
  end
end
