defmodule CineDieWeb.PageController do
  use CineDieWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
