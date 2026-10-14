defmodule JumonTest.ErrorHTML do
  @moduledoc "Error pages for the test endpoint."

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule JumonTest.Router do
  @moduledoc "The router of the test endpoint."
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default, on_mount: [JumonTest.Auth, {Jumon.Live, JumonTest.Commands}] do
      live("/", JumonTest.PaletteLive)
      live("/issues/:id", JumonTest.PaletteLive, :issue)
    end

    live_session :server_history,
      on_mount: [JumonTest.Auth, {Jumon.Live, JumonTest.ServerCommands}] do
      live("/server", JumonTest.PaletteLive)
    end
  end
end

defmodule JumonTest.Endpoint do
  @moduledoc "A Phoenix endpoint for the `Jumon.Live` and `Jumon.Test` tests. It runs no server."
  use Phoenix.Endpoint, otp_app: :jumon

  plug(Plug.Session, store: :cookie, key: "_jumon_test", signing_salt: "jumon-test")
  plug(JumonTest.Router)
end

defmodule JumonTest.SQLiteRepo do
  @moduledoc "A repo on SQLite, for Jumon.History.Ecto."
  use Ecto.Repo, otp_app: :jumon, adapter: Ecto.Adapters.SQLite3
end

defmodule JumonTest.PostgresRepo do
  @moduledoc "A repo on PostgreSQL, for Jumon.History.Ecto."
  use Ecto.Repo, otp_app: :jumon, adapter: Ecto.Adapters.Postgres
end
