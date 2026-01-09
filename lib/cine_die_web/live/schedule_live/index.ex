defmodule CineDieWeb.ScheduleLive.Index do
  @moduledoc """
  LiveView principale pour afficher le programme cinéma.
  """
  use CineDieWeb, :live_view

  alias CineDie.Showtimes
  import CineDieWeb.ScheduleComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Showtimes.subscribe()
      # Vérifier si on doit lancer le scraping
      maybe_trigger_scraping()
    end

    socket =
      socket
      |> assign(:page_title, "Programme")
      |> assign(:loading, %{vox: false, cosmos: false, star: false})
      |> assign(:selected_cinemas, MapSet.new([:vox, :cosmos, :star]))
      |> load_schedules()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_cinema", %{"cinema" => cinema}, socket) do
    cinema_atom = String.to_existing_atom(cinema)

    selected =
      if MapSet.member?(socket.assigns.selected_cinemas, cinema_atom) do
        MapSet.delete(socket.assigns.selected_cinemas, cinema_atom)
      else
        MapSet.put(socket.assigns.selected_cinemas, cinema_atom)
      end

    socket =
      socket
      |> assign(:selected_cinemas, selected)
      |> filter_sessions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", %{"provider" => provider}, socket) do
    provider_atom = String.to_existing_atom(provider)

    Showtimes.request_refresh(provider_atom)

    socket =
      socket
      |> update(:loading, &Map.put(&1, provider_atom, true))
      |> put_flash(:info, "Actualisation de #{provider_name(provider_atom)} en cours...")

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_all", _, socket) do
    Showtimes.request_refresh(:vox)
    Showtimes.request_refresh(:cosmos)
    Showtimes.request_refresh(:star)

    socket =
      socket
      |> assign(:loading, %{vox: true, cosmos: true, star: true})
      |> put_flash(:info, "Actualisation de tous les cinémas en cours...")

    {:noreply, socket}
  end

  @impl true
  def handle_event("recalculate", %{"provider" => provider}, socket) do
    provider_atom = String.to_existing_atom(provider)

    Showtimes.recalculate(provider_atom)

    socket =
      socket
      |> update(:loading, &Map.put(&1, provider_atom, true))
      |> put_flash(:info, "Recalcul de #{provider_name(provider_atom)} en cours...")

    {:noreply, socket}
  end

  @impl true
  def handle_event("recalculate_all", _, socket) do
    Showtimes.recalculate(:vox)
    Showtimes.recalculate(:cosmos)
    Showtimes.recalculate(:star)

    socket =
      socket
      |> assign(:loading, %{vox: true, cosmos: true, star: true})
      |> put_flash(:info, "Recalcul de tous les cinémas en cours...")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:showtimes_updated, provider}, socket) do
    socket =
      socket
      |> update(:loading, &Map.put(&1, provider, false))
      |> load_schedules()
      |> put_flash(:info, "#{provider_name(provider)} mis à jour!")

    {:noreply, socket}
  end

  defp load_schedules(socket) do
    all_sessions = Showtimes.list_by_day()

    socket
    |> assign(:all_sessions, all_sessions)
    |> filter_sessions()
  end

  defp filter_sessions(%{assigns: assigns} = socket) do
    selected = assigns.selected_cinemas |> MapSet.to_list() |> Enum.map(&Atom.to_string/1)

    # Get the current cinema week (starts on Wednesday)
    {_year, _week, wednesday} = Showtimes.current_cinema_week()

    # Create a map of date -> sessions from existing data
    sessions_by_date =
      (assigns[:all_sessions] || [])
      |> Enum.into(%{}, fn day -> {day.date, day.sessions} end)

    # Generate all 7 days from Wednesday to Tuesday
    days =
      0..6
      |> Enum.map(fn offset ->
        date = Date.add(wednesday, offset)

        sessions =
          sessions_by_date
          |> Map.get(date, [])
          |> Enum.filter(&(&1.cinema in selected))

        %{date: date, sessions: sessions}
      end)

    assign(socket, :days, days)
  end

  defp maybe_trigger_scraping do
    # Si pas de données pour cette semaine, lancer le scraping
    unless Showtimes.data_exists?(:vox), do: Showtimes.request_refresh(:vox)
    unless Showtimes.data_exists?(:cosmos), do: Showtimes.request_refresh(:cosmos)
    unless Showtimes.data_exists?(:star), do: Showtimes.request_refresh(:star)
  end

  defp provider_name(:vox), do: "Vox"
  defp provider_name(:cosmos), do: "Cosmos"
  defp provider_name(:star), do: "Star"
end
