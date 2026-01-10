defmodule CineDie.Showtimes do
  @moduledoc """
  Contexte pour gérer les programmes cinéma.
  """
  import Ecto.Query
  alias CineDie.Repo
  alias CineDie.Showtimes.{WeeklySchedule, ShowtimeData}

  @pubsub CineDie.PubSub
  @topic "showtimes"

  @doc "Liste les séances de la semaine cinéma courante (Mercredi-Mardi) pour les providers spécifiés"
  def list_current_week(providers \\ [:vox, :cosmos, :star]) do
    {year, week, _wednesday} = current_cinema_week()

    WeeklySchedule
    |> where([s], s.year == ^year and s.week_number == ^week)
    |> where([s], s.provider in ^providers)
    |> Repo.all()
  end

  @doc "Retourne les séances groupées par jour"
  def list_by_day(providers \\ [:vox, :cosmos, :star]) do
    providers
    |> list_current_week()
    |> Enum.flat_map(&extract_sessions/1)
    |> Enum.group_by(fn session -> Date.to_iso8601(session.date) end)
    |> Enum.sort_by(fn {date, _} -> date end)
    |> Enum.map(fn {date, sessions} ->
      %{
        date: Date.from_iso8601!(date),
        sessions: Enum.sort_by(sessions, & &1.time)
      }
    end)
  end

  @doc "Vérifie si les données existent pour un provider et la semaine cinéma courante"
  def data_exists?(provider) do
    {year, week, _wednesday} = current_cinema_week()

    WeeklySchedule
    |> where([s], s.provider == ^provider and s.year == ^year and s.week_number == ^week)
    |> Repo.exists?()
  end

  @doc "Upsert les séances d'un provider pour la semaine cinéma courante"
  def upsert_schedule(provider, showtimes_data) when provider in [:vox, :cosmos, :star] do
    require Logger

    case ShowtimeData.validate(showtimes_data) do
      {:ok, validated} ->
        {year, week, wednesday} = current_cinema_week()

        Logger.debug(
          "[Showtimes] upsert for #{provider}: year=#{year}, week=#{week}, wednesday=#{wednesday}"
        )

        checksum = compute_checksum(validated)

        attrs = %{
          provider: provider,
          year: year,
          week_number: week,
          week_start: wednesday,
          showtimes: validated,
          fetched_at: DateTime.utc_now(),
          checksum: checksum
        }

        changeset = WeeklySchedule.changeset(%WeeklySchedule{}, attrs)
        Logger.debug("[Showtimes] changeset valid? #{changeset.valid?}")

        unless changeset.valid? do
          Logger.error("[Showtimes] changeset errors: #{inspect(changeset.errors)}")
        end

        result =
          Repo.insert(changeset,
            on_conflict: {:replace, [:showtimes, :fetched_at, :checksum, :updated_at]},
            conflict_target: [:provider, :year, :week_number]
          )

        case result do
          {:ok, _} = success ->
            broadcast_update(provider)
            success

          error ->
            error
        end

      {:error, changeset} ->
        Logger.error("[Showtimes] ShowtimeData validation failed: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc "Subscribe aux mises à jour"
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc "Déclenche un refresh asynchrone via Oban pour un provider"
  def request_refresh(provider) when provider in [:vox, :cosmos, :star] do
    worker = worker_for_provider(provider)

    %{}
    |> worker.new()
    |> Oban.insert()
  end

  @doc "Supprime les données d'un provider pour la semaine cinéma courante"
  def delete_current_week(provider) when provider in [:vox, :cosmos, :star] do
    {year, week, _wednesday} = current_cinema_week()

    WeeklySchedule
    |> where([s], s.provider == ^provider and s.year == ^year and s.week_number == ^week)
    |> Repo.delete_all()
  end

  @doc "Recalcule les données: supprime puis relance le scraping pour un provider"
  def recalculate(provider) when provider in [:vox, :cosmos, :star] do
    delete_current_week(provider)
    request_refresh(provider)
  end

  defp worker_for_provider(:vox), do: CineDie.Workers.VoxScraperWorker
  defp worker_for_provider(:cosmos), do: CineDie.Workers.CosmosScraperWorker
  defp worker_for_provider(:star), do: CineDie.Workers.StarScraperWorker

  defp broadcast_update(provider) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:showtimes_updated, provider})
  end

  @doc """
  Calcule la semaine cinéma courante (Mercredi-Mardi).

  Retourne {année, numéro_semaine, date_mercredi} où:
  - La semaine cinéma commence le mercredi
  - Le numéro de semaine est basé sur l'année du mercredi

  Exemple: un mardi sera dans la semaine du mercredi précédent.
  """
  def current_cinema_week(date \\ Date.utc_today()) do
    # Wednesday = 3 in Date.day_of_week (Mon=1, ..., Sun=7)
    day_of_week = Date.day_of_week(date)

    # Calculate how many days to go back to reach Wednesday
    # If today is Wed (3), go back 0. If Thu (4), go back 1. ... If Tue (2), go back 6.
    days_since_wednesday = rem(day_of_week - 3 + 7, 7)
    wednesday = Date.add(date, -days_since_wednesday)

    # Use a simple week number based on the year and week of the year
    # We use ISO week number of the Wednesday for consistency
    {year, week_number} = :calendar.iso_week_number(Date.to_erl(wednesday))

    {year, week_number, wednesday}
  end

  defp compute_checksum(data) do
    data
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp extract_sessions(%WeeklySchedule{} = schedule) do
    (schedule.showtimes["films"] || [])
    |> Enum.flat_map(fn film ->
      (film["sessions"] || [])
      |> Enum.map(fn session ->
        datetime = parse_datetime(session["datetime"])

        %{
          link: film["link"],
          film_title: film["title"],
          film_id: film["external_id"],
          director: film["director"],
          genre: film["genre"],
          duration_minutes: film["duration_minutes"],
          poster_url: film["poster_url"],
          datetime: datetime,
          date: DateTime.to_date(datetime),
          time: DateTime.to_time(datetime),
          version: session["version"],
          cinema: Atom.to_string(schedule.provider)
        }
      end)
    end)
  end

  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} ->
        dt

      _ ->
        # Essayer avec Z si pas de timezone
        case DateTime.from_iso8601(iso_string <> "Z") do
          {:ok, dt, _} -> dt
          _ -> DateTime.utc_now()
        end
    end
  end

  defp parse_datetime(_), do: DateTime.utc_now()
end
