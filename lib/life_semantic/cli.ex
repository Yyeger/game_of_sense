defmodule LifeSemantic.CLI do
  @moduledoc """
  Terminal renderer + tick loop.

  Run: `mix run -e "LifeSemantic.CLI.run(10)"` for 10 generations,
       `mix run -e "LifeSemantic.CLI.run(:infinity)"` to run until Ctrl-C.
  """

  alias LifeSemantic.{Grid, Cache}

  @cell_width 9

  def run(generations \\ 20) do
    render_frame(0, 0, 0)

    case generations do
      :infinity -> loop(:infinity)
      n when is_integer(n) -> loop(n)
    end
  end

  defp loop(0), do: :ok

  defp loop(remaining) do
    t0 = System.monotonic_time(:millisecond)
    {changed, spawned} = Grid.tick()
    dt = System.monotonic_time(:millisecond) - t0

    {gen, _, _} = Grid.generation()
    render_frame(gen, changed, spawned, dt)

    case remaining do
      :infinity -> loop(:infinity)
      n -> loop(n - 1)
    end
  end

  defp render_frame(gen, changed, spawned, dt \\ 0) do
    grid = Grid.snapshot()
    size = Grid.size()
    %{entries: cache_size} = Cache.stats()

    IO.write(IO.ANSI.clear() <> IO.ANSI.home())

    IO.puts(
      IO.ANSI.bright() <>
        "Game of Sense  " <>
        IO.ANSI.reset() <>
        "gen=#{gen}  changed=#{changed}  spawned=#{spawned}  cache=#{cache_size}  tick=#{dt}ms"
    )

    IO.puts(String.duplicate("-", size * (@cell_width + 1)))

    for y <- 0..(size - 1) do
      for x <- 0..(size - 1) do
        cell = Map.get(grid, {x, y})
        IO.write(format_cell(cell))
      end

      IO.puts("")
    end

    IO.puts("")
  end

  defp format_cell(nil), do: String.pad_trailing(" ·", @cell_width) <> " "

  defp format_cell(word) do
    color = color_for(word)
    display = word |> String.slice(0, @cell_width) |> String.pad_trailing(@cell_width)
    color <> display <> IO.ANSI.reset() <> " "
  end

  # Stable color per concept — hash the word into the 256-color palette.
  defp color_for(word) do
    hash = :erlang.phash2(word, 200) + 20
    "\e[38;5;#{hash}m"
  end
end
