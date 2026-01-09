defmodule CineDie.Providers.DateParser do
  @moduledoc """
  Parse les dates en format français vers DateTime UTC.

  ## Exemples

      iex> DateParser.parse_cosmos_date("Dim. 11.01 | 10H30")
      {:ok, ~U[2026-01-11 09:30:00Z]}

      iex> DateParser.parse_french_date("Dim. 11.01", "10H30")
      {:ok, ~U[2026-01-11 09:30:00Z]}
  """

  @doc """
  Parse une date Cosmos : "Dim. 11.01 | 10H30"
  Retourne {:ok, DateTime.t()} ou {:error, reason}
  """
  def parse_cosmos_date(text) when is_binary(text) do
    # Pattern: "Jour. DD.MM | HHhMM" ou "Jour. DD.MM | HH:MM"
    regex = ~r/(\w+)\.\s*(\d{1,2})\.(\d{2})\s*\|\s*(\d{1,2})[Hh:](\d{2})/i

    case Regex.run(regex, text) do
      [_, _day_name, day, month, hour, minute] ->
        build_datetime(day, month, hour, minute)
      _ ->
        {:error, {:invalid_format, text}}
    end
  end

  @doc """
  Parse une date française séparée : jour "Dim. 11.01", heure "10H30"
  """
  def parse_french_date(date_text, time_text) when is_binary(date_text) and is_binary(time_text) do
    date_regex = ~r/(\d{1,2})\.(\d{2})/
    time_regex = ~r/(\d{1,2})[Hh:](\d{2})/i

    with [_, day, month] <- Regex.run(date_regex, date_text),
         [_, hour, minute] <- Regex.run(time_regex, time_text) do
      build_datetime(day, month, hour, minute)
    else
      _ -> {:error, {:invalid_format, {date_text, time_text}}}
    end
  end

  @doc """
  Parse un timestamp Unix en DateTime UTC
  """
  def parse_unix_timestamp(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(timestamp) do
      {:ok, dt} -> {:ok, dt}
      {:error, _} -> {:error, {:invalid_timestamp, timestamp}}
    end
  end

  def parse_unix_timestamp(timestamp) when is_binary(timestamp) do
    case Integer.parse(timestamp) do
      {int, ""} -> parse_unix_timestamp(int)
      _ -> {:error, {:invalid_timestamp, timestamp}}
    end
  end

  # Private

  defp build_datetime(day, month, hour, minute) do
    year = current_or_next_year(month)

    with {day_int, ""} <- Integer.parse(day),
         {month_int, ""} <- Integer.parse(month),
         {hour_int, ""} <- Integer.parse(hour),
         {minute_int, ""} <- Integer.parse(minute),
         {:ok, date} <- Date.new(year, month_int, day_int),
         {:ok, time} <- Time.new(hour_int, minute_int, 0) do
      # Créer en Europe/Paris puis convertir en UTC
      naive = NaiveDateTime.new!(date, time)
      # Approximation : Paris est UTC+1 en hiver, UTC+2 en été
      # Pour simplifier, on soustrait 1 heure (CET)
      utc_naive = NaiveDateTime.add(naive, -3600, :second)
      {:ok, DateTime.from_naive!(utc_naive, "Etc/UTC")}
    else
      _ -> {:error, :invalid_date_components}
    end
  end

  defp current_or_next_year(month) do
    today = Date.utc_today()
    month_int = String.to_integer(month)

    # Si le mois est passé, c'est pour l'année prochaine
    if month_int < today.month - 1 do
      today.year + 1
    else
      today.year
    end
  end
end
