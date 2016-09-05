# Paddle

An Ecto Adapter for LDAP

**Currently work in progress:** you should not use this for now.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `paddle` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:paddle, "~> 0.1.0"}]
    end
    ```

  2. Ensure `paddle` is started before your application:

    ```elixir
    def application do
      [applications: [:paddle]]
    end
    ```
