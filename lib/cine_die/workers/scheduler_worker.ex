defmodule CineDie.Workers.SchedulerWorker do
  @moduledoc """
  Worker périodique qui déclenche le scraping de tous les providers.
  Configuré via Oban crontab pour s'exécuter toutes les 6 heures.
  """
  use Oban.Worker, queue: :scheduler

  require Logger

  alias CineDie.Workers.{VoxScraperWorker, CosmosScraperWorker}

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("[SchedulerWorker] Triggering all scrapers")

    # Insérer les jobs de scraping
    jobs = [
      VoxScraperWorker.new(%{}),
      CosmosScraperWorker.new(%{})
    ]

    Enum.each(jobs, fn job ->
      case Oban.insert(job) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.error("[SchedulerWorker] Failed to insert job: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
