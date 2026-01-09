defmodule CineDie.Repo do
  use Ecto.Repo,
    otp_app: :cine_die,
    adapter: Ecto.Adapters.Postgres
end
