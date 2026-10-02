# ============================================================================
# Solarized Dark Showcase: Elixir (Functional BEAM Telemetry Collector)
# ============================================================================

defmodule Core.Telemetry.Collector do
  @moduledoc """
  Concurrent telemetry collector with pattern matching and pipeline aggregation.
  """

  use GenServer
  require Logger
  import Bitwise
  alias Core.Telemetry.MetricSample

  @default_timeout 5_000
  @max_batch_size 0xFF

  @type severity :: :info | :warn | :critical | :fatal
  @type metric_value :: float() | integer()

  defstruct [:node_id, :region, samples: [], dropped: 0, active: true]

  defguard is_valid_score(val) when is_number(val) and val >= 0.0 and val <= 100.0

  @doc "Starts the telemetry collector process linked to the current supervision tree."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    node_id = Keyword.get(opts, :node_id, "node-primary-01")
    region = Keyword.get(opts, :region, :us_east)
    GenServer.start_link(__MODULE__, {node_id, region}, name: __MODULE__, timeout: @default_timeout)
  end

  @impl true
  def init({node_id, region}) do
    state = %__MODULE__{node_id: node_id, region: region, samples: [], dropped: 0, active: true}
    {:ok, state}
  end

  @spec classify_score(number()) :: {:ok, severity()} | {:error, atom()}
  def classify_score(score) when is_valid_score(score) and score >= 90.0, do: {:ok, :critical}
  def classify_score(score) when is_valid_score(score) and score >= 70.0, do: {:ok, :warn}
  def classify_score(score) when is_valid_score(score), do: {:ok, :info}
  def classify_score(_invalid), do: {:error, :out_of_bounds}

  @spec ingest_batch([map()], String.t()) :: {:ok, map()} | {:error, term()}
  def ingest_batch(raw_events, source_tag) when is_list(raw_events) do
    with {:ok, normalized} <- normalize_events(raw_events),
         true <- length(normalized) <= @max_batch_size do
      summary =
        normalized
        |> Enum.map(fn item -> Map.update(item, :score, 0.0, &(&1 * 1.0)) end)
        |> Enum.filter(fn %{score: s} -> s > 0.0 end)
        |> summarize_metrics(source_tag)

      {:ok, summary}
    else
      false -> {:error, :batch_overflow}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_events(events) do
    try do
      mapped =
        for raw <- events, is_binary(Map.get(raw, :id)) do
          %MetricSample{id: String.trim(raw.id), score: raw.score, flags: 1 <<< 2}
        end

      {:ok, mapped}
    rescue
      err in [ArgumentError, KeyError] ->
        Logger.warning("Failed to normalize batch: #{inspect(err)}")
        {:error, :malformed_payload}
    end
  end

  defp summarize_metrics(items, source_tag) do
    case items do
      [] ->
        %{source: source_tag, count: 0, status: :empty, mean: nil, active: false}

      list ->
        total = Enum.reduce(list, 0.0, fn %{score: s}, acc -> acc + s end)
        count = length(list)
        mean =
          if count > 0 do
            total / count
          else
            0.0
          end
        label = "source=#{source_tag} count=#{count}\n"
        %{source: label, count: count, status: :ready, mean: mean, active: true}
    end
  end
end
