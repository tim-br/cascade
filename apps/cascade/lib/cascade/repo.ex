defmodule Cascade.Repo do
  use Ecto.Repo,
    otp_app: :cascade,
    adapter: Ecto.Adapters.Postgres
end
