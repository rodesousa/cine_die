defmodule CineDie.Workers.StarScraperWorker do
  @moduledoc """
  Worker Oban pour scraper le cinéma Star.
  """
  use Oban.Worker,
    queue: :scraping,
    max_attempts: 3,
    priority: 1

  require Logger

  alias CineDie.Providers.{Provider, Star}
  alias CineDie.Showtimes

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.info("[StarScraperWorker] Starting scrape")

    case Provider.fetch_and_validate(Star) do
      {:ok, data} ->
        Logger.info("[StarScraperWorker] Found #{count_sessions(data)} sessions")

        case Showtimes.upsert_schedule(:star, data) do
          {:ok, _} ->
            Logger.info("[StarScraperWorker] Schedule saved")
            :ok

          {:error, %Ecto.Changeset{} = changeset} ->
            Logger.error("[StarScraperWorker] Save failed: #{inspect(changeset.errors)}")
            {:error, changeset}

          {:error, reason} ->
            Logger.error("[StarScraperWorker] Save failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("[StarScraperWorker] Validation failed: #{inspect(changeset.errors)}")
        {:error, changeset}

      {:error, reason} ->
        Logger.error("[StarScraperWorker] Scrape failed: #{inspect(reason)}")
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
