defmodule Paddle.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Supervisor.start_link([Paddle],
      strategy: :one_for_one,
      name: Paddle.Supervisor
    )
  end
end
