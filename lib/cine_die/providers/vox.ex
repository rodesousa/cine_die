defmodule CineDie.Providers.Vox do
  @moduledoc """
  Provider pour le Cinéma Vox Strasbourg.
  Scrape la page /horaires-et-seances/ qui contient toutes les séances.

  Structure HTML parsée:
  - div.hr_film contient toutes les infos d'un film
  - h2 a contient le titre et l'URL du film (avec film_id)
  - p.hr_dur contient "Durée : XhYY - Sortie : ..."
  - p.hr_real strong contient le réalisateur
  - p.genre strong contient le genre
  - img.hr_aff contient l'affiche
  - a[href*='/reserver/'] contient les séances
  """

  @behaviour CineDie.Providers.Provider

  require Logger

  @base_url "https://www.cine-vox.com"
  @showtimes_url "#{@base_url}/horaires-et-seances/"
  @booking_regex ~r{/reserver/F(\d+)/D(\d+)/(VF|VO(?:STFR)?)/(\d+)/?}

  @impl true
  def cinema_info do
    %{name: "Vox Strasbourg", url: @base_url, provider: :vox}
  end

  @impl true
  def fetch_raw do
    case Req.get(@showtimes_url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        # The Vox website uses iso-8859-1 (Latin-1) encoding, convert to UTF-8
        {:ok, convert_to_utf8(body)}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Convert from ISO-8859-1 (Latin-1) to UTF-8
  defp convert_to_utf8(body) when is_binary(body) do
    body
    |> :unicode.characters_to_binary(:latin1, :utf8)
    |> case do
      result when is_binary(result) -> result
      _ -> body
    end
  end

  @impl true
  def to_showtime_data(html) when is_binary(html) do
    doc = Floki.parse_document!(html)

    films =
      doc
      |> Floki.find("div.hr_film")
      |> Enum.map(&parse_film_element/1)
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

  # Parse un élément div.hr_film complet
  defp parse_film_element(element) do
    # Extract film ID and title from h2 a
    title_link = element |> Floki.find("h2 a") |> List.first()

    if title_link do
      href = Floki.attribute(title_link, "href") |> List.first() || ""
      title = Floki.text(title_link) |> String.trim()

      film_id = case Regex.run(~r{/film/(\d+)/}, href) do
        [_, id] -> id
        _ -> nil
      end

      if film_id do
        %{
          "external_id" => film_id,
          "title" => title,
          "director" => extract_director(element),
          "duration_minutes" => extract_duration(element),
          "genre" => extract_genre(element),
          "poster_url" => extract_poster(element),
          "sessions" => extract_sessions(element, film_id)
        }
      else
        nil
      end
    else
      nil
    end
  end

  # Extract duration from p.hr_dur: "Durée : 1h26 - Sortie : ..."
  defp extract_duration(element) do
    duration_text =
      element
      |> Floki.find("p.hr_dur")
      |> Floki.text()
      |> to_string()

    # Pattern matches "Durée : 1h26" or "Durée : 2h"
    case Regex.run(~r/(\d+)h(\d+)?/, duration_text) do
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

  # Extract director from p.hr_real strong
  defp extract_director(element) do
    element
    |> Floki.find("p.hr_real strong")
    |> Floki.text()
    |> String.trim()
    |> nilify()
  end

  # Extract genre from p.genre strong
  defp extract_genre(element) do
    element
    |> Floki.find("p.genre strong")
    |> Floki.text()
    |> String.trim()
    |> nilify()
  end

  # Extract poster from img.hr_aff
  defp extract_poster(element) do
    element
    |> Floki.find("img.hr_aff")
    |> Floki.attribute("src")
    |> List.first()
  end

  # Extract sessions from booking links within this film element
  defp extract_sessions(element, film_id) do
    element
    |> Floki.find("a[href*='/reserver/']")
    |> Enum.map(&parse_booking_link/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn s -> s.film_id == film_id end)
    |> Enum.map(fn s ->
      %{
        "datetime" => DateTime.to_iso8601(s.datetime),
        "room" => "Salle #{s.room_id}",
        "version" => s.version,
        "booking_url" => s.booking_url,
        "session_id" => "#{s.film_id}-#{s.room_id}-#{DateTime.to_unix(s.datetime)}"
      }
    end)
  end

  defp parse_booking_link(element) do
    href = Floki.attribute(element, "href") |> List.first() || ""

    case Regex.run(@booking_regex, href) do
      [_full, film_id, timestamp, version, room_id] ->
        case Integer.parse(timestamp) do
          {ts, ""} ->
            {:ok, datetime} = DateTime.from_unix(ts)

            # href can be absolute or relative
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
              room_id: room_id,
              booking_url: booking_url
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
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
