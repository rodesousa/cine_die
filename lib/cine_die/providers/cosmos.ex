defmodule CineDie.Providers.Cosmos do
  @moduledoc """
  Provider pour le Cinéma Le Cosmos (Strasbourg).
  Scrape la page /agenda/ qui liste tous les films avec leurs séances.
  """

  @behaviour CineDie.Providers.Provider

  require Logger

  @base_url "https://cinema-cosmos.eu"
  @agenda_url "#{@base_url}/agenda/"

  @impl true
  def cinema_info do
    %{name: "Le Cosmos", url: @base_url, provider: :cosmos}
  end

  @impl true
  def fetch_raw do
    case Req.get(@agenda_url, receive_timeout: 30_000) do
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
    info = cinema_info()

    # Essayer plusieurs selecteurs pour trouver les films
    films =
      doc
      |> find_film_elements()
      |> Enum.map(&parse_article/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(fn film -> Enum.empty?(film["sessions"]) end)

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

  # Trouve les elements de films avec differents selecteurs possibles
  defp find_film_elements(doc) do
    selectors = [
      ".wpgb-card",
      ".wpgb-card-wrapper",
      "article.seance",
      "article[class*='seance']",
      ".seance"
    ]

    Enum.find_value(selectors, [], fn selector ->
      elements = Floki.find(doc, selector)
      if Enum.any?(elements), do: elements, else: nil
    end) || []
  end

  # Parse un article de film
  defp parse_article(article) do
    # Extraire l'ID depuis l'attribut id de l'article (ex: "post-43906")
    article_id =
      article
      |> Floki.attribute("id")
      |> List.first()
      |> case do
        nil -> "unknown"
        id -> String.replace(id, "post-", "")
      end

    # Titre du film - dans le heading principal
    title = extract_title(article)

    # Lien vers la page du film
    link = extract_film_link(article)

    # Réalisateur
    director = extract_director(article)

    # Durée depuis la ligne d'info (FR | 1H14 | 2021)
    duration = extract_duration(article)

    # Poster
    poster_url = extract_poster(article)

    # Séances groupées par salle
    sessions = extract_sessions(article)

    %{
      "external_id" => article_id,
      "title" => title,
      "link" => link,
      "director" => director,
      "duration_minutes" => duration,
      "genre" => nil,
      "poster_url" => poster_url,
      "sessions" => sessions
    }
  end

  defp extract_title(article) do
    # Le titre est généralement dans un h2 ou h3 avec un lien
    article
    |> Floki.find("h2 a, h3 a, .entry-title a, .seance-titre a")
    |> List.first()
    |> case do
      nil ->
        # Fallback: chercher juste le heading
        article
        |> Floki.find("h2, h3, .entry-title")
        |> Floki.text()
        |> String.trim()

      element ->
        Floki.text(element) |> String.trim()
    end
  end

  defp extract_film_link(article) do
    article
    |> Floki.find("h2 a, h3 a, .entry-title a, .seance-titre a")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_director(article) do
    # Le réalisateur est souvent après le titre
    # Chercher dans les éléments de texte qui contiennent des noms
    text =
      article
      |> Floki.find(".seance-realisateur, .entry-content > p:first-child")
      |> Floki.text()
      |> String.trim()

    if text == "" do
      # Fallback: chercher le texte juste après le titre
      article
      |> Floki.text()
      |> extract_director_from_text()
    else
      text
    end
  end

  defp extract_director_from_text(text) do
    # Pattern pour trouver le réalisateur après le titre
    # Généralement format "Prénom Nom, Prénom Nom"
    case Regex.run(~r/\n\s*([A-Z][a-zéèêëàâäùûüôöîï]+\s+[A-Z][a-zéèêëàâäùûüôöîï\-]+(?:,\s*[A-Z][a-zéèêëàâäùûüôöîï]+\s+[A-Z][a-zéèêëàâäùûüôöîï\-]+)*)\s*\n/, text) do
      [_, director] -> String.trim(director)
      _ -> nil
    end
  end

  defp extract_duration(article) do
    # Chercher le pattern "1H14" ou "1H22" dans le texte
    text = Floki.text(article)

    case Regex.run(~r/(\d+)H(\d+)/i, text) do
      [_, hours, minutes] ->
        String.to_integer(hours) * 60 + String.to_integer(minutes)

      _ ->
        nil
    end
  end

  defp extract_poster(article) do
    article
    |> Floki.find("img")
    |> Floki.attribute("src")
    |> List.first()
  end

  defp extract_sessions(article) do
    # Les séances sont dans des liens avec le format "SAM. 10.01 | 10H30 | VF"
    # Chercher les liens de reservation (billetterie, ticketingcine, etc.)

    article
    |> Floki.find("a[href*='billetterie'], a[href*='reservation'], a[href*='ticketingcine']")
    |> Enum.map(&parse_session_link/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_session_link(link_element) do
    href = Floki.attribute(link_element, "href") |> List.first() || ""
    text = Floki.text(link_element) |> String.trim()

    # Format attendu: "SAM. 10.01 | 10H30 | VF" ou "DIM. 01.02 | 10H40 | VF"
    case parse_session_text(text) do
      {:ok, datetime, version} ->
        %{
          "datetime" => DateTime.to_iso8601(datetime),
          "version" => version,
          "booking_url" => href,
          "session_id" => extract_session_id(href)
        }

      _ ->
        nil
    end
  end

  defp parse_session_text(text) do
    # Pattern: "JOUR. DD.MM | HHhMM|VERSION" ou "JOUR. DD.MM | HHhMM | VERSION"
    # Le pipe avant VERSION peut avoir ou non un espace
    regex = ~r/(\w+)\.\s*(\d{1,2})\.(\d{2})\s*\|\s*(\d{1,2})[Hh:](\d{2})\s*\|?\s*(\w+)/i

    case Regex.run(regex, text) do
      [_, _day_name, day, month, hour, minute, version] ->
        case build_datetime(day, month, hour, minute) do
          {:ok, datetime} -> {:ok, datetime, normalize_version(version)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp build_datetime(day, month, hour, minute) do
    year = current_or_next_year(month)

    with {day_int, ""} <- Integer.parse(day),
         {month_int, ""} <- Integer.parse(month),
         {hour_int, ""} <- Integer.parse(hour),
         {minute_int, ""} <- Integer.parse(minute),
         {:ok, date} <- Date.new(year, month_int, day_int),
         {:ok, time} <- Time.new(hour_int, minute_int, 0) do
      naive = NaiveDateTime.new!(date, time)
      {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
    else
      _ -> {:error, :invalid_date}
    end
  end

  defp current_or_next_year(month) do
    today = Date.utc_today()
    month_int = String.to_integer(month)

    if month_int < today.month - 1 do
      today.year + 1
    else
      today.year
    end
  end

  defp normalize_version(version) do
    case String.upcase(version) do
      "VF" -> "VF"
      "VO" -> "VO"
      "VOSTFR" -> "VOSTFR"
      "VOST" -> "VOSTFR"
      _ -> "VF"
    end
  end

  defp extract_session_id(href) do
    case Regex.run(~r/id=([^&]+)/, href) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp count_sessions(films) do
    Enum.reduce(films, 0, fn film, acc ->
      acc + length(Map.get(film, "sessions", []))
    end)
  end
end
