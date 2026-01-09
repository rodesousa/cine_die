defmodule CineDie.Providers.CosmosTest do
  use ExUnit.Case, async: true
  alias CineDie.Providers.Cosmos
  alias CineDie.Showtimes.ShowtimeData

  describe "cinema_info/0" do
    test "retourne les infos du cinema" do
      info = Cosmos.cinema_info()
      assert info.name == "Le Cosmos"
      assert info.provider == :cosmos
      assert String.starts_with?(info.url, "https://")
    end
  end

  describe "to_showtime_data/1 avec donnees simulees" do
    test "transforme une liste de seances en structure valide" do
      # Simuler les donnees raw (ce que fetch_raw retournerait)
      seances = [
        %{
          slug: "test-film",
          title: "Test Film",
          director: "Test Director",
          duration: 120,
          country: "FR",
          poster_url: "https://example.com/poster.jpg",
          sessions: [
            %{
              datetime: ~U[2026-01-09 14:00:00Z],
              room: "Grande salle",
              version: "VF",
              booking_url: "https://ticketingcine.com?id=123",
              session_id: "123"
            }
          ]
        }
      ]

      assert {:ok, data} = Cosmos.to_showtime_data(seances)
      assert {:ok, _validated} = ShowtimeData.validate(data)
    end

    test "metadata est correcte" do
      seances = [
        %{
          slug: "test",
          title: "Test",
          director: nil,
          duration: nil,
          country: nil,
          poster_url: nil,
          sessions: [
            %{
              datetime: ~U[2026-01-09 14:00:00Z],
              room: "Salle",
              version: "VF",
              booking_url: nil,
              session_id: nil
            }
          ]
        }
      ]

      {:ok, data} = Cosmos.to_showtime_data(seances)

      assert data["metadata"]["cinema_name"] == "Le Cosmos"
      assert data["metadata"]["total_sessions"] == 1
    end
  end
end
