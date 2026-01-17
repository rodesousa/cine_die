defmodule CineDie.Providers.VoxTest do
  use ExUnit.Case, async: true
  alias CineDie.Providers.Vox
  alias CineDie.Showtimes.ShowtimeData

  defp html(), do: Vox.fetch_raw() |> elem(1)

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
      assert {:ok, data} = Vox.to_showtime_data(html())
      assert {:ok, _validated} = ShowtimeData.validate(data)
    end

    test "extrait des films avec sessions" do
      {:ok, data} = Vox.to_showtime_data(html())

      assert length(data["films"]) > 0

      data["films"]
      |> Enum.at(6)

      film =
        hd(data["films"])

      assert film["external_id"]
      assert film["title"]
      assert length(film["sessions"]) > 0
    end

    test "sessions ont les champs requis" do
      {:ok, data} = Vox.to_showtime_data(html())

      film = hd(data["films"])
      session = hd(film["sessions"])

      assert session["datetime"]
      assert session["version"] in ["VF", "VOSTFR", "VO"]
    end

    test "metadata est correcte" do
      {:ok, data} = Vox.to_showtime_data(html())

      assert data["metadata"]["cinema_name"] == "Vox Strasbourg"
      assert data["metadata"]["total_sessions"] > 0
      assert data["metadata"]["fetched_at"]
    end

    test "extrait la duree comme string" do
      {:ok, data} = Vox.to_showtime_data(html())

      film = hd(data["films"])
      assert is_binary(film["duration"]) or is_nil(film["duration"])
    end
  end
end
