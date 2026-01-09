defmodule CineDie.Workers.CosmosScraperWorker do
  @moduledoc """
  Worker Oban pour scraper le cinéma Cosmos.
  """
  use Oban.Worker,
    queue: :scraping,
    max_attempts: 3,
    priority: 1

  require Logger

  alias CineDie.Providers.{Provider, Cosmos}
  alias CineDie.Showtimes

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.info("[CosmosScraperWorker] Starting scrape")

    case Provider.fetch_and_validate(Cosmos) do
      {:ok, data} ->
        Logger.info("[CosmosScraperWorker] Found #{count_sessions(data)} sessions")

        case Showtimes.upsert_schedule(:cosmos, data) do
          {:ok, _} ->
            Logger.info("[CosmosScraperWorker] Schedule saved")
            :ok

          {:error, reason} ->
            Logger.error("[CosmosScraperWorker] Save failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("[CosmosScraperWorker] Scrape failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp count_sessions(data) do
    data
    |> Map.get("films", [])
    |> Enum.reduce(0, fn film, acc ->
      acc + length(Map.get(film, "sessions", []))
    end)
  end
end
