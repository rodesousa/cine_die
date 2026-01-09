defmodule CineDie.Repo.Migrations.CreateWeeklySchedules do
  use Ecto.Migration

  def change do
    create table(:weekly_schedules) do
      add :provider, :string, null: false
      add :week_start, :date, null: false
      add :week_number, :integer, null: false
      add :year, :integer, null: false
      add :showtimes, :jsonb, null: false, default: "{}"
      add :fetched_at, :utc_datetime
      add :checksum, :string, size: 64

      timestamps(type: :utc_datetime)
    end

    create unique_index(:weekly_schedules, [:provider, :year, :week_number])
    create index(:weekly_schedules, [:week_start])
    create index(:weekly_schedules, [:showtimes], using: :gin)
  end
end
