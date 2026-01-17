defmodule CineDie.Showtimes.ShowtimeData do
  @moduledoc """
  Schema de validation pour les donnees de seances de cinema.

  Ce module utilise des embedded schemas Ecto pour valider la structure
  des donnees avant leur stockage en JSONB. La fonction `validate/1`
  retourne un map pur (sans structs) pret pour l'insertion en base.

  ## Structure attendue

      %{
        "films" => [
          %{
            "external_id" => "123",
            "title" => "Film Title",
            "director" => "Director Name",
            "duration" => "2h00",
            "genre" => "Action",
            "poster_url" => "https://...",
            "sessions" => [
              %{
                "datetime" => "2026-01-09T14:00:00Z",
                "room" => "Salle 1",
                "version" => "VF",
                "booking_url" => "https://...",
                "session_id" => "sess123"
              }
            ]
          }
        ],
        "metadata" => %{
          "cinema_name" => "Cinema Name",
          "cinema_url" => "https://...",
          "total_sessions" => 1,
          "fetched_at" => "2026-01-09T10:00:00Z"
        }
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    embeds_many :films, Film, primary_key: false do
      field :external_id, :string
      field :link, :string
      field :title, :string
      field :director, :string
      field :duration, :string
      field :genre, :string
      field :poster_url, :string

      embeds_many :sessions, Session, primary_key: false do
        field :datetime, :string
        field :version, :string
        field :session_id, :string
      end
    end

    embeds_one :metadata, Metadata, primary_key: false do
      field :cinema_name, :string
      field :cinema_url, :string
      field :total_sessions, :integer
      field :fetched_at, :string
    end
  end

  @valid_versions ~w(VF VOSTFR VO)

  @doc """
  Valide les donnees de seances et retourne un map pur (sans structs).

  ## Exemples

      iex> data = %{"films" => [...], "metadata" => %{...}}
      iex> {:ok, validated} = ShowtimeData.validate(data)
      iex> is_map(validated)
      true

  """
  @spec validate(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def validate(data) when is_map(data) do
    changeset = changeset(%__MODULE__{}, data)

    if changeset.valid? do
      {:ok, to_map(changeset)}
    else
      {:error, changeset}
    end
  end

  defp changeset(struct, params) do
    struct
    |> cast(params, [])
    |> cast_embed(:films, required: true, with: &film_changeset/2)
    |> cast_embed(:metadata, required: true, with: &metadata_changeset/2)
    |> validate_films_not_nil()
  end

  defp validate_films_not_nil(changeset) do
    case get_field(changeset, :films) do
      nil -> add_error(changeset, :films, "can't be nil")
      _ -> changeset
    end
  end

  defp film_changeset(struct, params) do
    struct
    |> cast(params, [
      :link,
      :external_id,
      :title,
      :director,
      :duration,
      :genre,
      :poster_url
    ])
    |> validate_required([:external_id, :title, :duration])
    |> cast_embed(:sessions, required: true, with: &session_changeset/2)
  end

  defp session_changeset(struct, params) do
    struct
    |> cast(params, [:datetime, :version, :session_id])
    |> validate_required([:datetime])
    |> validate_inclusion(:version, @valid_versions)
  end

  defp metadata_changeset(struct, params) do
    struct
    |> cast(params, [:cinema_name, :cinema_url, :total_sessions, :fetched_at])
    |> validate_required([:cinema_name])
  end

  @doc """
  Convertit un changeset valide en map pur (sans structs).
  """
  def to_map(changeset) do
    data = apply_changes(changeset)

    %{
      "films" => Enum.map(data.films, &film_to_map/1),
      "metadata" => metadata_to_map(data.metadata)
    }
  end

  defp film_to_map(film) do
    %{
      "link" => film.link,
      "external_id" => film.external_id,
      "title" => film.title,
      "director" => film.director,
      "duration" => film.duration,
      "genre" => film.genre,
      "poster_url" => film.poster_url,
      "sessions" => Enum.map(film.sessions, &session_to_map/1)
    }
  end

  defp session_to_map(session) do
    %{
      "datetime" => session.datetime,
      "version" => session.version,
      "session_id" => session.session_id
    }
  end

  defp metadata_to_map(metadata) do
    %{
      "cinema_name" => metadata.cinema_name,
      "cinema_url" => metadata.cinema_url,
      "total_sessions" => metadata.total_sessions,
      "fetched_at" => metadata.fetched_at
    }
  end
end
