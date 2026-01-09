defmodule CineDie.Providers.Cosmos do
  @moduledoc """
  Provider pour le Cinéma Le Cosmos (Strasbourg).
  Utilise le sitemap XML + scraping des pages de séances.
  """

  @behaviour CineDie.Providers.Provider

  import SweetXml
  require Logger

  @base_url "https://cinema-cosmos.eu"
  @sitemap_url "#{@base_url}/seance-sitemap.xml"

  @impl true
  def cinema_info do
    %{name: "Le Cosmos", url: @base_url, provider: :cosmos}
  end

  @impl true
  def fetch_raw do
    with {:ok, seance_urls} <- fetch_seance_urls(),
         {:ok, seances} <- fetch_all_seances(seance_urls) do
      {:ok, seances}
    end
  end

  @impl true
  def to_showtime_data(seances) when is_list(seances) do
    info = cinema_info()

    films =
      seances
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(fn s -> Enum.empty?(s.sessions) end)
      |> Enum.map(&format_film/1)

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

  # Récupère les URLs des séances depuis le sitemap
  defp fetch_seance_urls do
    case Req.get(@sitemap_url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        urls =
          body
          |> xpath(~x"//url/loc/text()"ls)
          # Filter seance pages but exclude the main archive page /seance/
          |> Enum.filter(fn url ->
            String.contains?(url, "/seance/") and not String.ends_with?(url, "/seance/")
          end)

        {:ok, urls}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Récupère toutes les pages de séances en parallèle
  defp fetch_all_seances(urls) do
    seances =
      urls
      |> Task.async_stream(&fetch_seance_page/1,
        max_concurrency: 5,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {:ok, seance}} -> seance
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, seances}
  end

  # Récupère et parse une page de séance
  defp fetch_seance_page(url) do
    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body}} ->
        parse_seance_page(body, url)

      _ ->
        {:error, :fetch_failed}
    end
  rescue
    e -> {:error, e}
  end

  defp parse_seance_page(html, source_url) do
    doc = Floki.parse_document!(html)

    title = extract_title(doc)
    slug = extract_slug(source_url)
    sessions = extract_sessions(doc)

    seance = %{
      slug: slug,
      title: title,
      director: extract_text(doc, ".card-realisateur"),
      duration: extract_duration(doc),
      country: extract_text(doc, ".card-country"),
      poster_url: extract_poster(doc),
      sessions: sessions
    }

    {:ok, seance}
  end

  defp extract_title(doc) do
    # Get only the first h1.entry-title element
    title =
      doc
      |> Floki.find("h1.entry-title")
      |> List.first()
      |> case do
        nil -> ""
        element -> Floki.text(element) |> String.trim()
      end

    if title == "" do
      # Fallback to page title
      doc
      |> Floki.find("title")
      |> Floki.text()
      |> String.split(" - ")
      |> List.first()
      |> String.trim()
    else
      title
    end
  end

  defp extract_text(doc, selector) do
    doc |> Floki.find(selector) |> Floki.text() |> String.trim() |> nilify()
  end

  defp extract_duration(doc) do
    text = extract_text(doc, ".card-duree")

    case text && Regex.run(~r/(\d+)H(\d+)?/i, text) do
      [_, hours, minutes] ->
        String.to_integer(hours) * 60 + String.to_integer(minutes || "0")

      [_, hours] ->
        String.to_integer(hours) * 60

      _ ->
        nil
    end
  end

  defp extract_poster(doc) do
    doc
    |> Floki.find("img.wp-post-image, .caps-img-seance img")
    |> Floki.attribute("src")
    |> List.first()
  end

  defp extract_sessions(doc) do
    current_room = "Salle principale"

    doc
    |> Floki.find("li.infos-reservation-salle, li.infos-reservation-item")
    |> Enum.reduce({current_room, []}, fn element, {room, sessions} ->
      class = Floki.attribute(element, "class") |> List.first() || ""

      cond do
        String.contains?(class, "infos-reservation-salle") ->
          new_room = Floki.find(element, "span") |> Floki.text() |> String.trim()
          {new_room, sessions}

        String.contains?(class, "infos-reservation-item") ->
          case parse_session(element, room) do
            {:ok, session} -> {room, [session | sessions]}
            _ -> {room, sessions}
          end

        true ->
          {room, sessions}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp parse_session(element, room) do
    link = Floki.find(element, "a") |> List.first()

    if link do
      href = Floki.attribute(link, "href") |> List.first() || ""
      text = Floki.text(link) |> String.trim()
      version = extract_version(element)

      case CineDie.Providers.DateParser.parse_cosmos_date(text) do
        {:ok, datetime} ->
          {:ok,
           %{
             datetime: datetime,
             room: room,
             version: version,
             booking_url: href,
             session_id: extract_session_id(href)
           }}

        _ ->
          {:error, :invalid_date}
      end
    else
      {:error, :no_link}
    end
  end

  defp extract_version(element) do
    features =
      element
      |> Floki.find("li.feature-agenda")
      |> Enum.map(&Floki.text/1)
      |> Enum.map(&String.upcase/1)
      |> Enum.map(&String.trim/1)

    cond do
      "VOSTFR" in features -> "VOSTFR"
      "VO" in features and "ST" in features -> "VOSTFR"
      "VO" in features -> "VO"
      "VF" in features -> "VF"
      true -> "VF"
    end
  end

  defp extract_slug(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
    |> List.last() || "unknown"
  end

  defp extract_session_id(href) do
    case Regex.run(~r/id=([^&]+)/, href) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp format_film(seance) do
    %{
      "external_id" => seance.slug,
      "title" => seance.title,
      "director" => seance.director,
      "duration_minutes" => seance.duration,
      "genre" => nil,
      "poster_url" => seance.poster_url,
      "sessions" =>
        Enum.map(seance.sessions, fn s ->
          %{
            "datetime" => DateTime.to_iso8601(s.datetime),
            "room" => s.room,
            "version" => s.version,
            "booking_url" => s.booking_url,
            "session_id" => s.session_id
          }
        end)
    }
  end

  defp count_sessions(films) do
    Enum.reduce(films, 0, fn film, acc ->
      acc + length(Map.get(film, "sessions", []))
    end)
  end

  defp nilify(""), do: nil
  defp nilify(str), do: str
end
