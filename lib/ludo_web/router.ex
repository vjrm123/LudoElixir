defmodule LudoWeb.Router do
  use LudoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LudoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end
  
  scope "/", LudoWeb do
    pipe_through :browser

    live_session :ludo do
      live "/",                InicioLive,   :index
      live "/lobby/:codigo",   LobbyLive,    :index
      live "/tablero/:codigo", TableroLive,  :index
    end
  end

  if Application.compile_env(:ludo, :dev_routes) do

    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LudoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
