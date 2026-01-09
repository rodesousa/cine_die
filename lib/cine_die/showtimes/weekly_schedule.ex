defmodule CineDie.Showtimes.WeeklySchedule do
  @moduledoc """
  Schema pour stocker les séances d'un cinéma pour une semaine.

  Chaque ligne = 1 provider + 1 semaine ISO.
  Le champ `showtimes` est un JSONB validé par ShowtimeData.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @providers [:vox, :cosmos, :star]

  schema "weekly_schedules" do
    field :provider, Ecto.Enum, values: @providers
    field :week_start, :date
    field :week_number, :integer
    field :year, :integer
    field :showtimes, :map
    field :fetched_at, :utc_datetime
    field :checksum, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :provider,
      :week_start,
      :week_number,
      :year,
      :showtimes,
      :fetched_at,
      :checksum
    ])
    |> validate_required([:provider, :week_start, :week_number, :year, :showtimes])
    |> validate_inclusion(:provider, @providers)
    |> validate_week_start_is_wednesday()
    |> unique_constraint([:provider, :year, :week_number])
  end

  defp validate_week_start_is_wednesday(changeset) do
    validate_change(changeset, :week_start, fn :week_start, date ->
      # Wednesday = 3 in Date.day_of_week (Monday=1, ..., Sunday=7)
      if Date.day_of_week(date) == 3 do
        []
      else
        [week_start: "must be a Wednesday"]
      end
    end)
  end

  def providers, do: @providers
end
