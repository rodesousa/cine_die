defmodule CineDie.Workers.VoxScraperWorker do
  @moduledoc """
  Worker Oban pour scraper le cinéma Vox.
  """
  use Oban.Worker,
    queue: :scraping,
    max_attempts: 3,
    priority: 1

  require Logger

  alias CineDie.Providers.{Provider, Vox}
  alias CineDie.Showtimes

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.info("[VoxScraperWorker] Starting scrape")

    case Provider.fetch_and_validate(Vox) do
      {:ok, data} ->
        Logger.info("[VoxScraperWorker] Found #{count_sessions(data)} sessions")
        Logger.debug("[VoxScraperWorker] Calling upsert_schedule...")

        result = Showtimes.upsert_schedule(:vox, data)
        Logger.debug("[VoxScraperWorker] upsert_schedule returned: #{inspect(result, limit: 500)}")

        case result do
          {:ok, _} ->
            Logger.info("[VoxScraperWorker] Schedule saved")
            :ok

          {:error, %Ecto.Changeset{} = changeset} ->
            Logger.error("[VoxScraperWorker] Save failed with changeset: #{inspect(changeset.errors)}")
            {:error, changeset}

          {:error, reason} ->
            Logger.error("[VoxScraperWorker] Save failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("[VoxScraperWorker] Validation failed: #{inspect(changeset.errors)}")
        {:error, changeset}

      {:error, reason} ->
        Logger.error("[VoxScraperWorker] Scrape failed: #{inspect(reason)}")
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
