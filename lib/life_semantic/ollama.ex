defmodule LifeSemantic.Ollama do
  @moduledoc """
  Minimal Ollama client. Sends a transition prompt and returns a single
  lowercase concept word (or :empty).
  """

  @url "http://localhost:11434/api/generate"
  @model "qwen3.5:2b"

  # Keep the system prompt tiny: every token is re-evaluated per call.
  @system "Semantic Game of Life. Given a cell + 8 neighbors, output ONE lowercase word (the emergent concept) or - for empty. No explanation."

  @doc """
  Ask the LLM for the new concept at a cell given its current value and
  the list of 8 neighbors (each either a string or nil).
  """
  def transition(current, neighbors) do
    prompt = build_prompt(current, neighbors)

    body = %{
      model: @model,
      system: @system,
      prompt: prompt,
      stream: false,
      # qwen3.5 is a hybrid thinking model — disable for speed.
      think: false,
      # Pin the model in VRAM so bursts don't pay the reload cost.
      keep_alive: "10m",
      options: %{
        temperature: 0.8,
        top_p: 0.9,
        num_predict: 4,
        stop: ["\n", " ", ",", "."]
      }
    }

    case Req.post(@url, json: body, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"response" => resp}}} ->
        resp |> strip_thinking() |> parse_response()

      {:ok, other} ->
        {:error, {:bad_response, other.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Defensive: even with think:false, some Ollama versions leak <think>…</think>
  # blocks into `response`. Strip them before parsing.
  defp strip_thinking(text) do
    text
    |> String.replace(~r/<think>.*?<\/think>/s, "")
    |> String.trim()
  end

  defp build_prompt(current, neighbors) do
    cur = current || "-"
    ns = neighbors |> Enum.map(fn nil -> "-"; v -> v end) |> Enum.join(",")
    "cell=#{cur} neighbors=#{ns} -> "
  end

  defp parse_response(resp) do
    word =
      resp
      |> String.trim()
      |> String.downcase()
      |> String.split(~r/[^a-z\-]/, trim: true)
      |> List.first()

    cond do
      word in [nil, "", "-"] -> {:ok, nil}
      String.length(word) > 20 -> {:ok, String.slice(word, 0, 20)}
      true -> {:ok, word}
    end
  end
end
