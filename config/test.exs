import Config

config :paddle, Paddle,
  schema_files: Path.wildcard("/etc/ldap/schema/*.schema"),
  host: ["192.168.42.42", "localhost"],
  base: "dc=test,dc=com",
  ssl: false,
  port: 3389,
  timeout: 50,
  ipv6: false
