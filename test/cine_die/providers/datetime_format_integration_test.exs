defmodule CineDie.Providers.DatetimeFormatIntegrationTest do
  @moduledoc """
  Test d'integration pour verifier le format ISO8601 des datetime
  avec des donnees reelles (pas de mock) pour les 3 providers.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias CineDie.Providers.{Vox, Cosmos, Star}

  @iso8601_regex ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

  describe "format datetime ISO8601 avec donnees reelles" do
    test "Vox: toutes les sessions ont un datetime au format ISO8601" do
      case Vox.fetch_raw() do
        {:ok, html} ->
          {:ok, data} = Vox.to_showtime_data(html)

          assert length(data["films"]) > 0, "Aucun film trouve pour Vox"

          for film <- data["films"], session <- film["sessions"] do
            assert session["datetime"] =~ @iso8601_regex,
                   "Format datetime invalide pour Vox: #{session["datetime"]} (film: #{film["title"]})"
          end

        {:error, reason} ->
          flunk("Impossible de recuperer les donnees Vox: #{inspect(reason)}")
      end
    end

    test "Cosmos: toutes les sessions ont un datetime au format ISO8601" do
      case Cosmos.fetch_raw() do
        {:ok, html} ->
          {:ok, data} = Cosmos.to_showtime_data(html)

          assert length(data["films"]) > 0, "Aucun film trouve pour Cosmos"

          for film <- data["films"], session <- film["sessions"] do
            assert session["datetime"] =~ @iso8601_regex,
                   "Format datetime invalide pour Cosmos: #{session["datetime"]} (film: #{film["title"]})"
          end

        {:error, reason} ->
          flunk("Impossible de recuperer les donnees Cosmos: #{inspect(reason)}")
      end
    end

    test "Star: toutes les sessions ont un datetime au format ISO8601" do
      case Star.fetch_raw() do
        {:ok, html} ->
          {:ok, data} = Star.to_showtime_data(html)

          assert length(data["films"]) > 0, "Aucun film trouve pour Star"

          for film <- data["films"], session <- film["sessions"] do
            assert session["datetime"] =~ @iso8601_regex,
                   "Format datetime invalide pour Star: #{session["datetime"]} (film: #{film["title"]})"
          end

        {:error, reason} ->
          flunk("Impossible de recuperer les donnees Star: #{inspect(reason)}")
      end
    end
  end
end
