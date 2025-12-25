defmodule CascadeWeb.PageController do
  use CascadeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
