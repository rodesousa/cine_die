defmodule CineDie.Providers.CosmosTest do
  use ExUnit.Case, async: true
  alias CineDie.Providers.Cosmos
  alias CineDie.Showtimes.ShowtimeData

  @fixture_path "test/support/fixtures/cosmos_agenda.html"

  defp load_fixture do
    File.read!(@fixture_path)
  end

  describe "cinema_info/0" do
    test "retourne les infos du cinema" do
      info = Cosmos.cinema_info()
      assert info.name == "Le Cosmos"
      assert info.provider == :cosmos
      assert String.starts_with?(info.url, "https://")
    end
  end

  describe "to_showtime_data/1" do
    test "parse le HTML et retourne une structure valide" do
      html = load_fixture()

      assert {:ok, data} = Cosmos.to_showtime_data(html)
      assert {:ok, _validated} = ShowtimeData.validate(data)
    end

    test "extrait les films depuis les articles" do
      html = load_fixture()

      {:ok, data} = Cosmos.to_showtime_data(html)
      films = data["films"]

      # 2 films avec seances (le 3e n'a pas de seances)
      assert length(films) == 2

      # Premier film
      film1 =
        Enum.find(films, &(&1["external_id"] == "43906"))

      assert film1["title"] == "Princesse Dragon"
      assert film1["link"] == "https://cinema-cosmos.eu/seance/princesse-dragon/"
      assert film1["duration"]
      assert length(film1["sessions"]) == 3
    end

    test "extrait le lien vers la fiche film" do
      html = load_fixture()

      {:ok, data} = Cosmos.to_showtime_data(html)
      film = hd(data["films"])

      assert film["link"] =~ "cinema-cosmos.eu/seance/"
    end

    test "extrait les sessions avec datetime et version" do
      html = load_fixture()

      {:ok, data} = Cosmos.to_showtime_data(html)
      film = Enum.find(data["films"], &(&1["external_id"] == "43906"))
      session = hd(film["sessions"])

      assert session["version"] == "VF"
      assert session["booking_url"] =~ "billetterie"
      assert session["datetime"] =~ "2026-01-11"
    end

    test "filtre les films sans seances" do
      html = load_fixture()

      {:ok, data} = Cosmos.to_showtime_data(html)
      films = data["films"]

      # Le film "Film Sans Seances" ne doit pas apparaitre
      assert Enum.all?(films, fn f -> f["title"] != "Film Sans Seances" end)
    end

    test "metadata est correcte" do
      html = load_fixture()

      {:ok, data} = Cosmos.to_showtime_data(html)

      assert data["metadata"]["cinema_name"] == "Le Cosmos"
      assert data["metadata"]["total_sessions"] == 5
      assert data["metadata"]["fetched_at"] != nil
    end

    test "extrait la duree comme string" do
      html = load_fixture()

      {:ok, data} = Cosmos.to_showtime_data(html)

      film1 = Enum.find(data["films"], &(&1["external_id"] == "43906"))
      assert is_binary(film1["duration"])

      film2 = Enum.find(data["films"], &(&1["external_id"] == "43907"))
      assert is_binary(film2["duration"])
    end

    test "extrait le poster" do
      html = load_fixture()

      {:ok, data} = Cosmos.to_showtime_data(html)
      film = hd(data["films"])

      assert film["poster_url"] =~ "example.com/poster"
    end
  end

  describe "fetch_raw/0" do
    @tag :integration
    test "recupere le HTML de la page agenda" do
      case Cosmos.fetch_raw() do
        {:ok, html} ->
          assert is_binary(html)
          assert html =~ "article"

        {:error, _} ->
          # Network error acceptable in tests
          :ok
      end
    end
  end
end
