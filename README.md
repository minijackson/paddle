# Paddle

[![hex.pm version](https://img.shields.io/hexpm/v/paddle.svg)](https://hex.pm/packages/paddle)
[![Build Status](https://travis-ci.org/minijackson/paddle.svg?branch=master)](https://travis-ci.org/minijackson/paddle)
[![Deps Status](https://beta.hexfaktor.org/badge/all/github/minijackson/paddle.svg)](https://beta.hexfaktor.org/github/minijackson/paddle)
[![Prod Deps Status](https://beta.hexfaktor.org/badge/prod/github/minijackson/paddle.svg)](https://beta.hexfaktor.org/github/minijackson/paddle)
[![Inline docs](http://inch-ci.org/github/minijackson/paddle.svg)](http://inch-ci.org/github/minijackson/paddle)

A library simplifying LDAP usage in Elixir projects.

[Documentation](https://hexdocs.pm/paddle/Paddle.html)

## Why another LDAP library?

If you want to communicate with an LDAP server in Elixir, you probably know
that there are other libraries out there. However, I didn't find one that
suited me:

- The [`:eldap`](http://erlang.org/doc/man/eldap.html) library is great, but
  very low-level, with no high-level features.

- [EctoLdap](https://github.com/jeffweiss/ecto_ldap) is very interesting, but I
  needed the add / modify / delete operations (in fact, I even wanted to do an
  Ecto adapter at first).

- [Exldap](https://github.com/jmerriweather/exldap) and
  [LDAPEx](https://github.com/OvermindDL1/ldap_ex) are both a translation of
  the LDAP `:eldap` in Elixir, which is nice, but are still missing some
  higher-level features.

## Usage

Once installed and configured, it allows you to quickly authenticate users:

```elixir
iex> Paddle.authenticate("myUser", "password")
:ok
```

Get meaningful information using [Paddle.Class](https://hexdocs.pm/paddle/Paddle.Class.html) structs:

```elixir
iex> Paddle.get %MyApp.PosixAccount{uid: "myUser"}
{:ok,
 [%MyApp.PosixAccount{cn: ["My User"], description: nil,
   gecos: ["My User,,,,"], gidNumber: ["120"],
   homeDirectory: ["/home/myuser"], host: nil, l: nil,
   loginShell: ["/bin/bash"], o: nil, ou: nil, seeAlso: nil, uid: ["myUser"],
   uidNumber: ["500"],
   userPassword: ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}]}
```

Or get information just about anything:

```elixir
iex> Paddle.get base: [ou: "People"], filter: [objectClass: "organizationalUnit"]
{:ok,
 [%{"dn" => "ou=People,dc=test,dc=com",
    "objectClass" => ["top", "organizationalUnit"], "ou" => ["People"]}]}
```

Add, delete, modify operations are supported. If you want to know more, just
go to [the documentation](https://hexdocs.pm/paddle/Paddle.html).

## Installation

The package can be installed as:

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

3. Add your configuration in your config files:

    ```elixir
    config :paddle, Paddle,
      host: "ldap.my-organisation.org",
      base: "dc=myorganisation,dc=org",
      ssl: true,
      port: 636
    ```

    For more configurations, see the [`Paddle` module docmumentation](https://hexdocs.pm/paddle/Paddle.html#module-configuration).

## Testing

If you want to test this application, you can use the linux commands
described in the [.travis.yml](.travis.yml) file in the
`before_script` block to start a local test LDAP server.

Keep in mind that you may need to change the
[.travis/ldap/slapd.conf](.travis/ldap/slapd.conf) for your system by changing
some configuration paths.

If you want to add some more data to the test server, please feel free
to issue a pull request.
