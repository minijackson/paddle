defmodule Paddle do
  @moduledoc ~S"""
  Module handling ldap requests and translate them to the `:eldap` syntax.

  Configuration
  -------------

  The configuration should be in the dev.secret.exs or prod.secret.exs depending
  on the environment you're working on. Here's an example config:

      config :paddle, Paddle,
        host: "ldap.my-organisation.org",
        base: "dc=myorganisation,dc=org",
        where: "People",
        ssl: true,
        port: 636

  The `:host` key is mandatory. By default, it establish a non SSL
  connection with 389 as port. The default `:base` is nothing, and the default
  `:where`, corresponding to the `ou` key in a LDAP structure, is `"People"`.

  Usage
  -----

  To check a user's credentials, simply do:

      Paddle.check_credentials("username", "password")

  """

  use GenServer
  require Logger

  alias Paddle.Parsing

  @type ldap_conn :: :eldap.handle
  @type auth_status :: :ok | {:error, atom}

  unless Application.get_env(:paddle, Paddle) do
    raise """
    Please configure the LDPA in the config files
    See the `Paddle` module documentation.
    """
  end

  @settings Application.get_env :paddle, Paddle

  unless Dict.get(@settings, :host) do
    raise "Please configure a :host in the Paddle configuration"
  end

  @host Dict.get(@settings, :host) |> :erlang.binary_to_list
  @ssl  Dict.get(@settings, :ssl, false)
  @port Dict.get(@settings, :port, 389)

  @base  Dict.get(@settings, :base, "")        |> :erlang.binary_to_list
  @where Dict.get(@settings, :where, "People") |> :erlang.binary_to_list

  @subbase 'ou=' ++ @where ++ ',' ++ @base

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

    if @ssl, do: Application.ensure_all_started(:ssl)

    Logger.info("Connecting to ldap#{if @ssl, do: "s"}://#{@host}:#{@port}")

    {:ok, ldap_conn} = :eldap.open([@host], ssl: @ssl, port: @port)
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
    dn = Parsing.construct_dn([uid: username, ou: @where], @base)
    Logger.debug "Checking credentials with dn: #{dn}"
    status = :eldap.simple_bind(ldap_conn, dn, password)

   case status do
     :ok -> {:reply, status, ldap_conn}
     {:error, :invalidCredentials} -> {:reply, {:error, :invalid_credentials}, ldap_conn}
     {:error, :anonymous_auth} -> {:reply, status, ldap_conn}
    end

  end

  def handle_call({:get, kwdn}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, @base)
    Logger.debug("Getting entries with dn: #{dn}")
    {:reply,
     :eldap.search(ldap_conn, base: dn, filter: :eldap.present('objectClass'))
     |> clean_eldap_search_result,
     ldap_conn}
  end

  def handle_call({:get_single, kwdn}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, @base)
    Logger.debug("Getting single entry with dn: #{dn}")
    {:reply,
     :eldap.search(ldap_conn,
                   base: dn,
                   scope: :eldap.baseObject,
                   filter: :eldap.present('objectClass'))
      |> clean_eldap_search_result,
     ldap_conn}
  end

  @spec check_credentials(charlist | binary, charlist | binary) :: boolean

  @doc ~S"""
  Check the given credentials.

  Because we are using an Erlang library, we must convert the username and
  password to a list of chars instead of an Elixir string.
  """
  def check_credentials(username, password) when is_list(username) and is_list(password) do
    GenServer.call(Paddle, {:authenticate, username, password})
  end

  def check_credentials(username, password) do
    check_credentials(:erlang.binary_to_list(username), :erlang.binary_to_list(password))
  end

  @doc ~S"""
  Get one or more LDAP entries given a keyword list.

  Example:

      iex> Paddle.get(uid: "testuser", ou: "People")
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
  def get(kwdn), do: GenServer.call(Paddle, {:get, kwdn})

  @doc ~S"""
  Get a single LDAP entry given a keyword list.

  Example:

      iex> Paddle.get_single(ou: "People")
      {:ok,
       [%{"dn" => "ou=People,dc=test,dc=com",
         "objectClass" => ["organizationalUnit"], "ou" => ["People"]}]}
  """
  def get_single(kwdn), do: GenServer.call(Paddle, {:get_single, kwdn})

  # =======================
  # == Private Utilities ==
  # =======================

  defp clean_eldap_search_result({:error, error} = error_tuple) do
    case error do
      :noSuchObject -> error_tuple
    end
  end

  defp clean_eldap_search_result({:ok, {:eldap_search_result, entries, []}}) do
    {:ok, Parsing.clean_entries(entries)}
  end

end
