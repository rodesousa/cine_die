defmodule CineDie.Providers.Provider do
  @moduledoc """
  Behaviour commun pour tous les providers de cinéma.

  CHAQUE provider DOIT implémenter :
  - `fetch_raw/0` : Récupère les données brutes (HTML, API, etc.)
  - `to_showtime_data/1` : Transforme les données brutes en format ShowtimeData
  - `cinema_info/0` : Retourne les infos du cinéma
  """

  alias CineDie.Showtimes.ShowtimeData

  @type raw_data :: term()
  @type cinema_info :: %{name: String.t(), url: String.t(), provider: atom()}

  @callback fetch_raw() :: {:ok, raw_data()} | {:error, term()}
  @callback to_showtime_data(raw_data()) :: {:ok, map()} | {:error, term()}
  @callback cinema_info() :: cinema_info()

  @doc """
  Pipeline complet : fetch -> transform -> validate
  Retourne {:ok, validated_map} ou {:error, reason}
  """
  def fetch_and_validate(provider_module) do
    with {:ok, raw} <- provider_module.fetch_raw(),
         {:ok, data} <- provider_module.to_showtime_data(raw),
         {:ok, validated} <- ShowtimeData.validate(data) do
      {:ok, validated}
    end
  end

  @doc "Calcule le checksum SHA256 des données"
  def compute_checksum(data) do
    data
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
