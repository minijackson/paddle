use Mix.Config

config :paddle, Paddle,
  host: "localhost",
  base: "dc=test,dc=com",
  where: "People",
  ssl: false,
  port: 3389
