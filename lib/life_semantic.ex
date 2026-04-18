defmodule LifeSemantic do
  @moduledoc """
  Game of Sense — Conway's Game of Life where cells are concepts (words)
  and the transition rule is a local LLM (Ollama + qwen3.5:2b). An ETS
  cache keyed on (current_concept, sorted_neighbors) collapses repeat
  inferences, and a few fresh seeds are injected per tick so the board
  doesn't degenerate to a handful of attractors.

  Quick start:

      iex -S mix
      iex> LifeSemantic.CLI.run(5)       # run 5 generations
      iex> LifeSemantic.Grid.reseed()    # randomize again
  """

  defdelegate run(generations), to: LifeSemantic.CLI
end
