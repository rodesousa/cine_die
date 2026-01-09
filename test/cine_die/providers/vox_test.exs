defmodule CineDie.Providers.VoxTest do
  use ExUnit.Case, async: true
  alias CineDie.Providers.Vox
  alias CineDie.Showtimes.ShowtimeData

  test "cc" do
    CineDie.Providers.Provider.fetch_and_validate(Vox)
    |> IO.inspect(label: " ")
  end

  describe "cinema_info/0" do
    test "retourne les infos du cinema" do
      info = Vox.cinema_info()
      assert info.name == "Vox Strasbourg"
      assert info.provider == :vox
      assert String.starts_with?(info.url, "https://")
    end
  end

  describe "to_showtime_data/1" do
    test "transforme HTML fixture en structure valide" do
      html = File.read!("test/support/fixtures/vox_horaires.html")

      assert {:ok, data} = Vox.to_showtime_data(html)
      assert {:ok, _validated} = ShowtimeData.validate(data)
    end

    test "extrait des films avec sessions" do
      html = File.read!("test/support/fixtures/vox_horaires.html")
      {:ok, data} = Vox.to_showtime_data(html)

      assert length(data["films"]) > 0

      film = hd(data["films"])

      film
      |> IO.inspect()

      assert film["external_id"]
      assert film["title"]
      assert length(film["sessions"]) > 0
    end

    test "sessions ont les champs requis" do
      html = File.read!("test/support/fixtures/vox_horaires.html")
      {:ok, data} = Vox.to_showtime_data(html)

      film = hd(data["films"])
      session = hd(film["sessions"])

      assert session["datetime"]
      assert session["room"]
      assert session["version"] in ["VF", "VOSTFR", "VO"]
    end

    test "metadata est correcte" do
      html = File.read!("test/support/fixtures/vox_horaires.html")
      {:ok, data} = Vox.to_showtime_data(html)

      assert data["metadata"]["cinema_name"] == "Vox Strasbourg"
      assert data["metadata"]["total_sessions"] > 0
      assert data["metadata"]["fetched_at"]
    end
  end
end
