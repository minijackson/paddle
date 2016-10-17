defmodule Paddle do
  @moduledoc ~S"""
  Module handling ldap requests and translate them to the `:eldap` syntax.

  ## Configuration

  The configuration should be in the dev.secret.exs or prod.secret.exs depending
  on the environment you're working on. Here's an example config:

      config :paddle, Paddle,
        host: "ldap.my-organisation.org",
        base: "dc=myorganisation,dc=org",
        user_subdn: "ou=People",
        ssl: true,
        port: 636,
        account_class: "inetOrgPerson"

  - `:host` - The host of the LDAP server. Mandatory
  - `:base` - The base DN.
  - `:user_subdn` - The DN (without the base) where the users are located.
    Defaults to `"ou=People"`.
  - `:ssl` - When set to `true`, use SSL to connect to the LDAP server.
    Defaults to `false`.
  - `:port` - The port the LDAP server listen to. Defaults to `389`.
  - `:account_class` - The class (objectClass) of all your user entries.
    Defaults to `"posixAccount"`

  ## Usage

  To check a user's credentials, simply do:

      Paddle.check_credentials("username", "password")

  Many functions support passing both a base and a filter via a keyword list
  like so:

      Paddle.get(filter: [uid: "testuser"], base: [ou: "People"])

  A filter in Paddle is a Keyword list and the atom corresponding to the key
  must have a value strictly equal to, well the given value. When multiple
  keywords are provided, the result must match all criteria.

  If you are missing some filtering capabilities, you can always pass as
  argument an `:eldap` filter like so:

      Paddle.get(filter: :eldap.substrings('uid', initial: 'b'))

  You are also provided with some "user" functions that will automatically get
  the information from the right "directory" and check that the entry have the
  right objectClass, see [Configuration](#module-configuration).

  Example:

      Paddle.users(filter: [givenName: "User"])
  """

  use GenServer
  require Logger

  alias Paddle.Parsing

  @type ldap_conn :: :eldap.handle
  @type ldap_entry :: %{required(binary) => binary}
  @type auth_status :: :ok | {:error, atom}

  @type eldap_dn :: charlist
  @type eldap_entry :: {:eldap_entry, eldap_dn, [{charlist, [charlist]}]}

  unless Application.get_env(:paddle, Paddle) do
    raise """
    Please configure the LDPA in the config files
    See the `Paddle` module documentation.
    """
  end

  @spec start_link() :: Genserver.on_start

  @doc ~S"""
  Start the LDAP process.

  This function is called by the supervisor handled by the main application
  in `MyApplication.start/2`.
  """
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: Paddle)
  end

  @spec init(:ok) :: {:ok, ldap_conn}

  @doc ~S"""
  Init the LDAP connection.

  This is called by the `GenServer.start_link/3` function. GenServer will then
  handle and keep the state, which is in this case the ldap connection, and
  pass it we we need it.
  """
  def init(:ok) do
    ssl  = config(:ssl)
    host = config(:host)
    port = config(:port)

    if ssl, do: Application.ensure_all_started(:ssl)

    Logger.info("Connecting to ldap#{if ssl, do: "s"}://#{host}:#{port}")

    {:ok, ldap_conn} = :eldap.open([host], ssl: ssl, port: port)
    Logger.info("Connected to LDAP")
    {:ok, ldap_conn}
  end

  @type reason :: :normal | :shutdown | {:shutdown, term} | term

  @spec terminate(reason, ldap_conn) :: :ok

  @doc ~S"""
  Terminate the LDAP connection.

  Called by GenServer when the process is stopped.
  """
  def terminate(_reason, ldap_conn) do
    :eldap.close(ldap_conn)
    Logger.info("Stopped LDAP")
  end

  def handle_call({:authenticate, username, password}, _from, ldap_conn) do
    dn = Parsing.construct_dn([uid: username], config(:userbase))
    Logger.debug "Checking credentials with dn: #{dn}"
    status = :eldap.simple_bind(ldap_conn, dn, password)

   case status do
     :ok -> {:reply, status, ldap_conn}
     {:error, :invalidCredentials} -> {:reply, {:error, :invalid_credentials}, ldap_conn}
     {:error, :anonymous_auth} -> {:reply, status, ldap_conn}
    end

  end

  def handle_call({:get, filter, kwdn, base}, _from, ldap_conn) do
    dn     = Parsing.construct_dn(kwdn, config(base))
    filter = Parsing.construct_filter(filter)
    Logger.debug("Getting entries with dn: #{dn} and filter: #{inspect filter}")
    {:reply,
     :eldap.search(ldap_conn, base: dn, filter: filter)
     |> clean_eldap_search_results,
     ldap_conn}
  end

  def handle_call({:get_single, filter, kwdn, base}, _from, ldap_conn) do
    dn     = Parsing.construct_dn(kwdn, config(base))
    filter = Parsing.construct_filter(filter)
    Logger.debug("Getting single entry with dn: #{dn} and filter: #{inspect filter}")
    {:reply,
     :eldap.search(ldap_conn,
                   base: dn,
                   scope: :eldap.baseObject,
                   filter: filter)
      |> clean_eldap_search_results
      |> ensure_single_result,
     ldap_conn}
  end

  @spec check_credentials(charlist | binary, charlist | binary) :: boolean

  @doc ~S"""
  Check the given credentials.

  Because we are using an Erlang library, we must convert the username and
  password to a list of chars instead of an Elixir string.

  Example:

      iex> Paddle.check_credentials("testuser", "test")
      :ok
      iex> Paddle.check_credentials("testuser", "wrong password")
      {:error, :invalid_credentials}
  """
  def check_credentials(username, password) when is_list(username) and is_list(password) do
    GenServer.call(Paddle, {:authenticate, username, password})
  end

  def check_credentials(username, password) do
    check_credentials(String.to_charlist(username), String.to_charlist(password))
  end

  @spec get(keyword) :: {:ok, [ldap_entry]} | {:error, :no_such_object}

  @doc ~S"""
  Get one or more LDAP entries given a keyword list.

  Example:

      iex> Paddle.get(base: [uid: "testuser", ou: "People"])
      {:ok,
       [%{"cn" => ["Test User"],
         "dn" => "uid=testuser,ou=People,dc=test,dc=com",
         "gecos" => ["Test User,,,,"], "gidNumber" => ["120"],
         "homeDirectory" => ["/home/testuser"],
         "loginShell" => ["/bin/bash"],
         "objectClass" => ["account", "posixAccount", "top"],
         "uid" => ["testuser"], "uidNumber" => ["500"],
         "userPassword" => ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}]}

      iex> Paddle.get(base: [uid: "nothing"])
      {:error, :no_such_object}

      iex> Paddle.get(filter: [uid: "testuser"], base: [ou: "People"])
      {:ok,
       [%{"cn" => ["Test User"],
         "dn" => "uid=testuser,ou=People,dc=test,dc=com",
         "gecos" => ["Test User,,,,"], "gidNumber" => ["120"],
         "homeDirectory" => ["/home/testuser"],
         "loginShell" => ["/bin/bash"],
         "objectClass" => ["account", "posixAccount", "top"],
         "uid" => ["testuser"], "uidNumber" => ["500"],
         "userPassword" => ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}]}
  """
  def get(kwdn) do
    GenServer.call(Paddle,
                   {:get,
                    Keyword.get(kwdn, :filter),
                    Keyword.get(kwdn, :base),
                    :base})
  end

  @spec get_single(keyword) :: {:ok, ldap_entry} | {:error, :no_such_object}

  @doc ~S"""
  Get a single LDAP entry given a keyword list.

  Example:

      iex> Paddle.get_single(base: [ou: "People"])
      {:ok,
       %{"dn" => "ou=People,dc=test,dc=com",
        "objectClass" => ["organizationalUnit"], "ou" => ["People"]}}

      iex> Paddle.get_single(filter: [uid: "nothing"])
      {:error, :no_such_object}
  """
  def get_single(kwdn) do
    GenServer.call(Paddle,
                   {:get_single,
                    Keyword.get(kwdn, :filter),
                    Keyword.get(kwdn, :base),
                    :base})
  end

  @spec users() :: {:ok, [ldap_entry]} | {:error, :no_such_object}

  @doc ~S"""
  Get all user entries.

  You can give an additional filter via the `filter:` keyword, but you are not
  allowed to specify the base.

  Example:

      iex> Paddle.users()
      {:ok,
       [%{"cn" => ["Test User"],
         "dn" => "uid=testuser,ou=People,dc=test,dc=com",
         "gecos" => ["Test User,,,,"], "gidNumber" => ["120"],
         "homeDirectory" => ["/home/testuser"],
         "loginShell" => ["/bin/bash"],
         "objectClass" => ["account", "posixAccount", "top"],
         "uid" => ["testuser"], "uidNumber" => ["500"],
         "userPassword" => ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}]}
  """
  def users(kwdn \\ []) do
    GenServer.call(Paddle,
                   {:get,
                    user_filter(Keyword.get(kwdn, :filter)),
                    Keyword.get(kwdn, :base),
                    :userbase})
  end

  @spec user(binary | charlist) :: {:ok, ldap_entry} | {:error, :no_such_object}

  @doc ~S"""
  Get a user entry given a uid.

  Example:

      iex> Paddle.user("testuser")
      {:ok,
       %{"cn" => ["Test User"],
        "dn" => "uid=testuser,ou=People,dc=test,dc=com",
        "gecos" => ["Test User,,,,"], "gidNumber" => ["120"],
        "homeDirectory" => ["/home/testuser"],
        "loginShell" => ["/bin/bash"],
        "objectClass" => ["account", "posixAccount", "top"],
        "uid" => ["testuser"], "uidNumber" => ["500"],
        "userPassword" => ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}}
  """
  def user(uid) do
    GenServer.call(Paddle,
                   {:get_single,
                    user_filter,
                    [uid: uid], :userbase})
  end

  # =======================
  # == Private Utilities ==
  # =======================

  @spec config :: keyword

  defp config, do: Application.get_env(:paddle, Paddle)

  @spec config(atom) :: any

  defp config(:host),          do: Keyword.get(config, :host)             |> String.to_charlist
  defp config(:ssl),           do: config(:ssl, false)
  defp config(:port),          do: config(:port, 389)
  defp config(:base),          do: config(:base, "")                      |> String.to_charlist
  defp config(:user_subdn),    do: config(:user_subdn, "ou=People")       |> String.to_charlist
  defp config(:userbase),      do: config(:user_subdn) ++ ',' ++ config(:base)
  defp config(:account_class), do: config(:account_class, "posixAccount") |> String.to_charlist

  @spec config(atom, any) :: any

  defp config(key, default), do: Keyword.get(config, key, default)

  @spec clean_eldap_search_results({:ok, {:eldap_search_result, [eldap_entry]}}
                                   | {:error, atom})
  :: {:ok, [ldap_entry]} | {:error, :no_such_object}

  defp clean_eldap_search_results({:error, error}) do
    case error do
      :noSuchObject -> {:error, :no_such_object}
    end
  end

  defp clean_eldap_search_results({:ok, {:eldap_search_result, [], []}}) do
    {:error, :no_such_object}
  end

  defp clean_eldap_search_results({:ok, {:eldap_search_result, entries, []}}) do
    {:ok, Parsing.clean_entries(entries)}
  end

  @spec ensure_single_result({:ok, [ldap_entry]} | {:error, :no_such_object})
  :: {:ok, ldap_entry} | {:error, :no_such_object}

  defp ensure_single_result({:error, error}) do
    case error do
      :no_such_object -> {:error, :no_such_object}
    end
  end

  defp ensure_single_result({:ok, []}), do: {:error, :no_such_object}
  defp ensure_single_result({:ok, [result]}), do: {:ok, result}

  defp user_filter, do: :eldap.equalityMatch('objectClass', config(:account_class))

  defp user_filter(nil), do: :eldap.equalityMatch('objectClass', config(:account_class))
  defp user_filter([]),  do: :eldap.equalityMatch('objectClass', config(:account_class))

  defp user_filter(filter) do
    filter = Parsing.construct_filter(filter)
    :eldap.and([filter, :eldap.equalityMatch('objectClass', config(:account_class))])
  end

end
