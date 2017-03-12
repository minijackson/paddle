use Mix.Config

config :paddle, Paddle,
  schema_files: Path.wildcard("/etc/ldap/schema/*.schema"),
  host: "localhost",
  base: "dc=test,dc=com",
  ssl: false,
  port: 3389
