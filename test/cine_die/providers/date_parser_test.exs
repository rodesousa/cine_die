defmodule CineDie.Providers.DateParserTest do
  use ExUnit.Case, async: true
  alias CineDie.Providers.DateParser

  describe "parse_cosmos_date/1" do
    test "parse une date valide" do
      assert {:ok, dt} = DateParser.parse_cosmos_date("Dim. 11.01 | 10H30")
      assert dt.day == 11
      assert dt.month == 1
      assert dt.hour == 10  # Heure locale conservee
      assert dt.minute == 30
    end

    test "parse avec format HH:MM" do
      assert {:ok, dt} = DateParser.parse_cosmos_date("Lun. 13.01 | 14:00")
      assert dt.day == 13
      assert dt.hour == 14  # Heure locale conservee
    end

    test "retourne erreur pour format invalide" do
      assert {:error, _} = DateParser.parse_cosmos_date("invalid")
      assert {:error, _} = DateParser.parse_cosmos_date("")
    end
  end

  describe "parse_unix_timestamp/1" do
    test "parse un timestamp integer" do
      assert {:ok, dt} = DateParser.parse_unix_timestamp(1767963600)
      assert dt.year == 2026
      assert dt.month == 1
      assert dt.day == 9
    end

    test "parse un timestamp string" do
      assert {:ok, dt} = DateParser.parse_unix_timestamp("1767963600")
      assert dt.year == 2026
    end

    test "retourne erreur pour timestamp invalide" do
      assert {:error, _} = DateParser.parse_unix_timestamp("invalid")
    end
  end
end
