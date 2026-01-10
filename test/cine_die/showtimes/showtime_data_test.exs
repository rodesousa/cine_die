defmodule CineDie.Showtimes.ShowtimeDataTest do
  use ExUnit.Case, async: true
  alias CineDie.Showtimes.ShowtimeData

  describe "validate/1" do
    test "valide une structure correcte" do
      data = valid_showtime_data()
      assert {:ok, result} = ShowtimeData.validate(data)
      assert is_map(result)
      assert length(result["films"]) == 1
    end

    test "rejette si films manquants" do
      data = %{"metadata" => valid_metadata()}
      assert {:error, changeset} = ShowtimeData.validate(data)
      refute changeset.valid?
    end

    test "rejette si version invalide" do
      data = valid_showtime_data()
      data = put_in(data, ["films", Access.at(0), "sessions", Access.at(0), "version"], "INVALID")
      assert {:error, _} = ShowtimeData.validate(data)
    end

    test "accepte VF, VOSTFR, VO" do
      for version <- ["VF", "VOSTFR", "VO"] do
        data = valid_showtime_data()
        data = put_in(data, ["films", Access.at(0), "sessions", Access.at(0), "version"], version)
        assert {:ok, _} = ShowtimeData.validate(data)
      end
    end

    test "rejette si datetime manquant dans session" do
      data = valid_showtime_data()
      data = put_in(data, ["films", Access.at(0), "sessions", Access.at(0), "datetime"], nil)
      assert {:error, _} = ShowtimeData.validate(data)
    end

    test "rejette si title manquant dans film" do
      data = valid_showtime_data()
      data = put_in(data, ["films", Access.at(0), "title"], nil)
      assert {:error, _} = ShowtimeData.validate(data)
    end
  end

  describe "to_map/1" do
    test "convertit struct en map pour JSONB" do
      data = valid_showtime_data()
      {:ok, validated} = ShowtimeData.validate(data)

      assert is_map(validated)
      refute is_struct(validated)

      film = hd(validated["films"])
      assert is_map(film)
      refute is_struct(film)

      session = hd(film["sessions"])
      assert is_map(session)
      refute is_struct(session)
    end

    test "datetime est converti en ISO8601 string" do
      data = valid_showtime_data()
      {:ok, validated} = ShowtimeData.validate(data)

      session = validated["films"] |> hd() |> Map.get("sessions") |> hd()
      assert is_binary(session["datetime"])
      assert String.contains?(session["datetime"], "T")
    end
  end

  # Helpers
  defp valid_showtime_data do
    %{
      "films" => [
        %{
          "external_id" => "123",
          "title" => "Test Film",
          "director" => "Test Director",
          "duration_minutes" => 120,
          "genre" => "Action",
          "poster_url" => "https://example.com/poster.jpg",
          "sessions" => [
            %{
              "datetime" => "2026-01-09T14:00:00Z",
              "room" => "Salle 1",
              "version" => "VF",
              "session_id" => "sess123"
            }
          ]
        }
      ],
      "metadata" => valid_metadata()
    }
  end

  defp valid_metadata do
    %{
      "cinema_name" => "Test Cinema",
      "cinema_url" => "https://test.com",
      "total_sessions" => 1,
      "fetched_at" => "2026-01-09T10:00:00Z"
    }
  end
end
