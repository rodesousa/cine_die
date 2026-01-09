defmodule CineDie.Providers.Star do
  @moduledoc """
  Provider pour le Cinéma Star Strasbourg.
  Scrape la page /horaires/ qui contient toutes les séances.

  Structure HTML parsée:
  - table.horaires contient les horaires par jour
  - Les liens de réservation ont le format /star/reserver/F{film_id}/D{timestamp}/{version}/
  - Les infos films sont dans des blocs avec titre, durée, réalisateur
  """

  @behaviour CineDie.Providers.Provider

  require Logger

  @base_url "https://www.cinema-star.com"
  @showtimes_url "#{@base_url}/horaires/"
  @booking_regex ~r{/star/reserver/F(\d+)/D(\d+)/(VF|VO(?:STFR)?)/}

  @impl true
  def cinema_info do
    %{name: "Star Strasbourg", url: @base_url, provider: :star}
  end

  @impl true
  def fetch_raw do
    case Req.get(@showtimes_url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def to_showtime_data(html) when is_binary(html) do
    doc = Floki.parse_document!(html)

    films =
      doc
      |> parse_films()
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(fn film -> Enum.empty?(film["sessions"]) end)

    info = cinema_info()

    data = %{
      "films" => films,
      "metadata" => %{
        "cinema_name" => info.name,
        "cinema_url" => info.url,
        "total_sessions" => count_sessions(films),
        "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    {:ok, data}
  end

  # Parse tous les films de la page
  # La structure de Cinema Star regroupe les films par blocs
  defp parse_films(doc) do
    # Trouver tous les liens de réservation et extraire les infos
    booking_links =
      doc
      |> Floki.find("a[href*='/star/reserver/']")
      |> Enum.map(&parse_booking_link/1)
      |> Enum.reject(&is_nil/1)

    # Grouper par film_id
    booking_links
    |> Enum.group_by(& &1.film_id)
    |> Enum.map(fn {film_id, sessions} ->
      # Trouver les infos du film dans la page
      film_info = extract_film_info(doc, film_id)

      %{
        "external_id" => film_id,
        "title" => film_info.title,
        "director" => film_info.director,
        "duration_minutes" => film_info.duration_minutes,
        "genre" => film_info.genre,
        "poster_url" => film_info.poster_url,
        "sessions" => Enum.map(sessions, fn s ->
          %{
            "datetime" => DateTime.to_iso8601(s.datetime),
            "room" => "Salle Star",
            "version" => s.version,
            "booking_url" => s.booking_url,
            "session_id" => "#{s.film_id}-#{DateTime.to_unix(s.datetime)}"
          }
        end)
      }
    end)
  end

  defp parse_booking_link(element) do
    href = Floki.attribute(element, "href") |> List.first() || ""

    case Regex.run(@booking_regex, href) do
      [_full, film_id, timestamp, version] ->
        case Integer.parse(timestamp) do
          {ts, ""} ->
            {:ok, datetime} = DateTime.from_unix(ts)

            booking_url =
              if String.starts_with?(href, "http") do
                href
              else
                @base_url <> href
              end

            %{
              film_id: film_id,
              datetime: datetime,
              version: normalize_version(version),
              booking_url: booking_url
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  # Extraire les infos d'un film à partir de son ID
  defp extract_film_info(doc, film_id) do
    # Chercher le lien vers la fiche film
    film_link_selector = "a[href*='/film/#{film_id}/']"

    film_block =
      doc
      |> Floki.find(film_link_selector)
      |> List.first()

    title =
      if film_block do
        Floki.text(film_block) |> String.trim() |> clean_title()
      else
        "Film #{film_id}"
      end

    # Chercher les infos autour du lien du film
    # On cherche le parent qui contient toutes les infos
    %{
      title: title,
      director: extract_text_after(doc, film_id, "Réalisé par"),
      duration_minutes: extract_duration(doc, film_id),
      genre: extract_genre(doc, film_id),
      poster_url: extract_poster(doc, film_id)
    }
  end

  defp clean_title(title) do
    title
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp extract_text_after(doc, film_id, prefix) do
    # Chercher dans le contexte du film
    doc
    |> Floki.text()
    |> String.split(~r/Film #{film_id}|#{prefix}/i)
    |> case do
      [_, after_prefix | _] ->
        after_prefix
        |> String.split("\n")
        |> List.first()
        |> String.trim()
        |> nilify()

      _ ->
        nil
    end
  end

  defp extract_duration(doc, _film_id) do
    # Chercher le pattern de durée dans le texte
    text = Floki.text(doc)

    case Regex.run(~r/(\d+)h(\d+)?/, text) do
      [_, hours, minutes] ->
        h = String.to_integer(hours)
        m = if minutes && minutes != "", do: String.to_integer(minutes), else: 0
        h * 60 + m

      [_, hours] ->
        String.to_integer(hours) * 60

      _ ->
        nil
    end
  end

  defp extract_genre(_doc, _film_id) do
    # Genre difficile à extraire sans structure claire
    nil
  end

  defp extract_poster(doc, film_id) do
    # Chercher l'image près du lien du film
    doc
    |> Floki.find("a[href*='/film/#{film_id}/'] img, a[href*='/film/#{film_id}/'] ~ img")
    |> Floki.attribute("src")
    |> List.first()
  end

  defp normalize_version("VF"), do: "VF"
  defp normalize_version("VO"), do: "VO"
  defp normalize_version("VOSTFR"), do: "VOSTFR"
  defp normalize_version(_), do: "VF"

  defp nilify(""), do: nil
  defp nilify(s), do: s

  defp count_sessions(films) do
    Enum.reduce(films, 0, fn film, acc ->
      acc + length(Map.get(film, "sessions", []))
    end)
  end
end
