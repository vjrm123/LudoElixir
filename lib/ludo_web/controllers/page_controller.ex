defmodule LudoWeb.PageController do
  use LudoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
