defmodule CineDie.Providers.StarTest do
  use ExUnit.Case, async: true
  alias CineDie.Providers.Star
  alias CineDie.Showtimes.ShowtimeData

  @fixture_path "test/support/fixtures/star_horaires.html"

  defp load_fixture do
    File.read!(@fixture_path)
  end

  describe "cinema_info/0" do
    test "retourne les infos du cinema" do
      info = Star.cinema_info()
      assert info.name == "Star Strasbourg"
      assert info.provider == :star
      assert String.starts_with?(info.url, "https://")
    end
  end

  describe "to_showtime_data/1" do
    test "parse le HTML et retourne une structure valide" do
      html = load_fixture()

      assert {:ok, data} = Star.to_showtime_data(html)
      assert {:ok, _validated} = ShowtimeData.validate(data)
    end

    test "extrait les films depuis les liens de reservation" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      films = data["films"]

      # 3 films avec seances (le 4e n'a pas de seances)
      assert length(films) == 3

      # Verifier qu'on a les bons film_ids
      film_ids = Enum.map(films, & &1["external_id"]) |> Enum.sort()
      assert film_ids == ["604102", "604200", "604400"]
    end

    test "extrait le titre depuis le lien du film" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      film = Enum.find(data["films"], &(&1["external_id"] == "604102"))

      assert film["title"] =~ "Anaconda"
    end

    test "extrait les sessions avec datetime et version" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      film = Enum.find(data["films"], &(&1["external_id"] == "604102"))

      assert length(film["sessions"]) == 3

      # Verifier les versions
      versions = Enum.map(film["sessions"], & &1["version"]) |> Enum.sort()
      assert versions == ["VF", "VF", "VO"]
    end

    test "extrait le booking_url complet" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      film = Enum.find(data["films"], &(&1["external_id"] == "604102"))
      session = hd(film["sessions"])

      assert session["booking_url"] =~ "cinema-star.com"
      assert session["booking_url"] =~ "/star/reserver/"
    end

    test "extrait le link du film depuis a.horaires-affiche" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      film = Enum.find(data["films"], &(&1["external_id"] == "604102"))

      assert film["link"] == "https://www.cinema-star.com/film/604102/"
    end

    test "extrait le titre depuis l'attribut title" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      film = Enum.find(data["films"], &(&1["external_id"] == "604200"))

      assert film["title"] == "Mufasa : Le Roi Lion"
    end

    test "filtre les films sans seances" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      films = data["films"]

      # Le film "Film Sans Seances" (604300) ne doit pas apparaitre
      assert Enum.all?(films, fn f -> f["external_id"] != "604300" end)
    end

    test "metadata est correcte" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)

      assert data["metadata"]["cinema_name"] == "Star Strasbourg"
      # 3 + 4 + 2 = 9 sessions
      assert data["metadata"]["total_sessions"] == 9
      assert data["metadata"]["fetched_at"] != nil
    end

    test "parse correctement les timestamps Unix" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      film = Enum.find(data["films"], &(&1["external_id"] == "604102"))
      session = hd(film["sessions"])

      # Le datetime doit etre une string ISO8601
      assert session["datetime"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
    end

    test "genere des session_id uniques" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)

      all_session_ids =
        data["films"]
        |> Enum.flat_map(& &1["sessions"])
        |> Enum.map(& &1["session_id"])

      # Tous les session_id doivent etre uniques
      assert length(all_session_ids) == length(Enum.uniq(all_session_ids))
    end

    test "normalise les versions correctement" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      film = Enum.find(data["films"], &(&1["external_id"] == "604200"))

      versions = Enum.map(film["sessions"], & &1["version"])
      assert "VOSTFR" in versions
      assert "VF" in versions
    end

    test "extrait le poster" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      film = Enum.find(data["films"], &(&1["external_id"] == "604102"))

      assert film["poster_url"] =~ "poster-anaconda"
    end

    test "extrait la duree comme string" do
      html = load_fixture()

      {:ok, data} = Star.to_showtime_data(html)
      film = hd(data["films"])

      assert is_binary(film["duration"]) or is_nil(film["duration"])
    end
  end

  describe "fetch_raw/0" do
    @tag :integration
    test "recupere le HTML de la page horaires" do
      case Star.fetch_raw() do
        {:ok, html} ->
          assert is_binary(html)
          assert html =~ "reserver"

        {:error, _} ->
          # Network error acceptable in tests
          :ok
      end
    end
  end
end
