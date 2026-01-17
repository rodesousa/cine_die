defmodule CineDieWeb.ScheduleComponents do
  @moduledoc """
  Composants Phoenix pour l'affichage des séances cinéma.
  """
  use Phoenix.Component
  import CineDieWeb.CoreComponents

  @doc """
  Checkbox pour filtrer par cinéma dans la sidebar.
  """
  attr :cinema, :atom, required: true
  attr :checked, :boolean, default: true
  attr :loading, :boolean, default: false

  def cinema_checkbox(assigns) do
    ~H"""
    <label class="flex items-center gap-3 p-2 rounded-lg hover:bg-gray-700 cursor-pointer transition-colors">
      <input
        type="checkbox"
        class="w-4 h-4 rounded border-gray-500 bg-gray-700 text-amber-500 focus:ring-amber-500"
        checked={@checked}
        phx-click="toggle_cinema"
        phx-value-cinema={@cinema}
      />
      <div class="flex items-center gap-2 flex-1">
        <div class={"w-2 h-2 rounded-full #{cinema_dot_color(@cinema)}"}></div>
        <span class="text-white font-medium">{cinema_name(@cinema)}</span>
        <.icon :if={@loading} name="hero-arrow-path" class="w-4 h-4 text-amber-500 animate-spin" />
      </div>
    </label>
    """
  end

  @doc """
  Colonne pour un jour de la semaine.
  """
  attr :day, :map, required: true

  def day_column(assigns) do
    ~H"""
    <div class="flex flex-col min-w-[200px]">
      <div class="sticky top-0 bg-gray-900 p-3 border-b border-gray-700 z-10">
        <h3 class="text-amber-500 font-bold">{format_day_name(@day.date)}</h3>
        <p class="text-gray-400 text-sm">{format_day_date(@day.date)}</p>
      </div>
      <div class="flex flex-col gap-3 p-2">
        <.session_card :for={session <- @day.sessions} session={session} />
        <div :if={Enum.empty?(@day.sessions)} class="text-gray-500 text-center py-8">
          Aucune séance
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Card pour une séance individuelle.
  """
  attr :session, :map, required: true

  def session_card(assigns) do
    ~H"""
    <div class={"bg-gray-800 rounded-r-lg p-3 border-l-4 #{cinema_border_color(@session.cinema)} hover:bg-gray-750 transition-colors"}>
      <div class="flex justify-between items-start mb-2">
        <span class="bg-gray-700 text-white px-2 py-1 rounded text-sm font-mono font-bold">
          {format_time(@session.time)}
        </span>
        <div class="flex items-center gap-2">
          <span :if={@session.duration} class="text-gray-400 text-xs">
            <.icon name="hero-clock" class="w-3 h-3 inline" />
            {@session.duration}
          </span>
        </div>
      </div>

      <h4 class="text-white font-semibold text-sm mb-1 line-clamp-2">
        {@session.film_title}
      </h4>

      <p :if={@session.director} class="text-gray-400 text-xs mb-2 line-clamp-1">
        {@session.director}
      </p>

      <div class="text-xs text-gray-400">
        <div class="flex items-center gap-1">
          <.icon name="hero-map-pin" class="w-3 h-3" />
          <span>{cinema_name(@session.cinema)}</span>
        </div>
      </div>

      <div :if={true} class="mt-3">
        <a
          href={@session.link}
          target="_blank"
          class="block w-full text-center bg-amber-600 hover:bg-amber-500 text-white text-xs py-2 px-3 rounded transition-colors"
        >
          Description
        </a>
      </div>
    </div>
    """
  end

  # Helpers

  defp cinema_name(:vox), do: "Vox"
  defp cinema_name(:cosmos), do: "Cosmos"
  defp cinema_name(:star), do: "Star"
  defp cinema_name("vox"), do: "Vox"
  defp cinema_name("cosmos"), do: "Cosmos"
  defp cinema_name("star"), do: "Star"
  defp cinema_name(_), do: "Cinéma"

  defp cinema_dot_color(:vox), do: "bg-blue-500"
  defp cinema_dot_color(:cosmos), do: "bg-green-500"
  defp cinema_dot_color(:star), do: "bg-purple-500"
  defp cinema_dot_color("vox"), do: "bg-blue-500"
  defp cinema_dot_color("cosmos"), do: "bg-green-500"
  defp cinema_dot_color("star"), do: "bg-purple-500"
  defp cinema_dot_color(_), do: "bg-gray-500"

  defp cinema_border_color("vox"), do: "border-blue-500"
  defp cinema_border_color("cosmos"), do: "border-green-500"
  defp cinema_border_color("star"), do: "border-purple-500"
  defp cinema_border_color(_), do: "border-gray-500"

  defp format_day_name(date) do
    day_names = %{
      1 => "Lundi",
      2 => "Mardi",
      3 => "Mercredi",
      4 => "Jeudi",
      5 => "Vendredi",
      6 => "Samedi",
      7 => "Dimanche"
    }

    Map.get(day_names, Date.day_of_week(date), "Jour")
  end

  defp format_day_date(date) do
    "#{date.day} #{month_name(date.month)}"
  end

  defp month_name(1), do: "Jan"
  defp month_name(2), do: "Fév"
  defp month_name(3), do: "Mar"
  defp month_name(4), do: "Avr"
  defp month_name(5), do: "Mai"
  defp month_name(6), do: "Juin"
  defp month_name(7), do: "Juil"
  defp month_name(8), do: "Août"
  defp month_name(9), do: "Sep"
  defp month_name(10), do: "Oct"
  defp month_name(11), do: "Nov"
  defp month_name(12), do: "Déc"

  defp format_time(%Time{} = time) do
    hour = time.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute = time.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{hour}:#{minute}"
  end
end
