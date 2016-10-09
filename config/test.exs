use Mix.Config

config :paddle, Paddle,
  host: "localhost",
  base: "dc=test,dc=com",
  user_subdn: "ou=People",
  ssl: false,
  port: 3389
