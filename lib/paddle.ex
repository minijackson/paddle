defmodule Paddle do
  @moduledoc ~S"""
  Module handling ldap requests and translate them to the `:eldap` syntax.

  ## Configuration

  The configuration should be in the dev.secret.exs or prod.secret.exs depending
  on the environment you're working on. Here's an example config:

      config :paddle, Paddle,
        host: "ldap.my-organisation.org",
        base: "dc=myorganisation,dc=org",
        ssl: true,
        port: 636,
        ipv6: true,
        tcpopts: [],
        sslopts: [certfile: '/path/to/certificate.crt'],
        timeout: 3000,
        account_subdn: "ou=People",
        schema_files: Path.wildcard("/etc/openldap/schema/*.schema"),
        filter_passwords: true

  Option    | Description | Default
  --------- | ----------- | -------
  `:host`   | The host(s) containing the LDAP server(s). Can be a bitstring for a single host, or a list of bitstrings, which will make Paddle try to connect to each host in the specified order. See also the `:timeout` option. | **Mandatory**
  `:base`   | The base DN. | `""`
  `:ssl`    | When set to `true`, use SSL to connect to the LDAP server. | `false`
  `:port`   | The port the LDAP server listen to. | `389`
  `:ipv6`   | When set to `true`, connect to the LDAP server using IPv6. | `false`
  `:tcpopts`| Additionnal `:gen_tcp.connect/4` / `:ssl.connect/4` options.  Must not have the `:active`, `:binary`, `:deliver`, `:list`, `:mode` or `:packet` options. See [`:gen_tcp`'s option documentation](http://erlang.org/doc/man/gen_tcp.html#type-connect_option).  | `[]`
  `:sslopts`| Additionnal `:ssl.connect/4` options. Ineffective if the `:ssl` option is set to `false`. See [`:ssl`'s option documentation](http://erlang.org/doc/man/ssl.html).  | `[]`
  `:timeout`| The timeout in milliseconds, or `nil` for the default TCP stack timeout value (which may be very long), for each request to the LDAP server. | `nil`
  `:account_subdn` | The DN (without the base) where the accounts are located. Used by the `Paddle.authenticate/2` function. | `"ou=People"`
  `:account_identifier` |  The identifier by which users are identified. Used by the `Paddle.authenticate/2` function. | `:uid`
  `:schema_files` | Files which are to be parsed to help generate classes using [`Paddle.Class.Helper`](Paddle.Class.Helper.html#module-using-schema-files).  | `[]`
  `:filter_passwords` | Filter passwords from appearing in the logs | `true`

  ## Usage

  To check a user's credentials and/or authenticate the connection, simply do:

      Paddle.authenticate("username", "password")

  You can also specify the partial DN like so:

      Paddle.authenticate([cn: "admin"], "adminpassword")

  Many functions support passing both a base and a filter via a keyword list
  or a map like so:

      Paddle.get(filter: [uid: "testuser"], base: [ou: "People"])

  But you can also use structs which implements the `Paddle.Class` protocol
  (called [class objects](#module-class-objects)). If we take as example the
  classes defined in `test/support/classes.ex`, we could do:

      Paddle.get %MyApp.PosixAccount{uid: "user"}

  The previous example will return every accounts which are in a given subDN
  (defined in the `Paddle.Class` protocol), which have the right objectClass
  (also defined in the same protocol), and have an uid of "user".

  You can also specify an additional [filter](#module-filters) as second
  argument.

  ## Class objects

  A class object is simply a struct implementing the `Paddle.Class` protocol.

  If you're in need of some examples, you can see the `test/support/classes.ex`
  file which defines `MyApp.PosixAccount`, and `MyApp.PosixGroup` (but only
  in test mode, so you would have to define your own).

  For more informations, see the `Paddle.Class` module documentation.

  ## Filters

  A filter in Paddle is a keyword list or a map.

  This is equivalent to a filter where each attribute name (key from the map /
  keyword list) must have a corresponding value (value from the map / keyword
  list).

  Example:

      [uid: "user", cn: "User", homeDirectory: "/home/user"]

  If you are missing some filtering capabilities, you can always pass as
  argument an `:eldap` filter like so:

      Paddle.get(filter: :eldap.substrings('uid', initial: 'b'))

  For more informations and examples, see `Paddle.Filters.construct_filter/1`

  ## Bases

  A base in Paddle can be a Keyword list that will be converted to a charlist
  to be passed on to the `:eldap` module. A direct string can also be passed.

  For more informations and examples, see `Paddle.Filters.construct_dn/2`
  """

  use GenServer
  require Logger

  alias Paddle.Parsing
  alias Paddle.Filters
  alias Paddle.Attributes

  @typep ldap_conn :: :eldap.handle() | {:not_connected, binary}
  @type ldap_entry :: %{required(binary) => binary}
  @type auth_status :: :ok | {:error, atom}

  @type dn :: keyword | binary

  unless Application.get_env(:paddle, __MODULE__) do
    raise """
    Please configure the LDAP in the config files
    See the `Paddle` module documentation.
    """
  end

  @spec start_link(term) :: Genserver.on_start()

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec init([]) :: {:ok, ldap_conn}

  @impl GenServer
  def init(opts \\ []) do
    case do_connect(opts) do
      {:ok, ldap_conn} -> {:ok, ldap_conn}
      {:error, reason} -> {:ok, {:not_connected, reason}}
    end
  end

  @type reason :: :normal | :shutdown | {:shutdown, term} | term

  @spec terminate(reason, ldap_conn) :: :ok

  @impl GenServer
  def terminate(_shutdown_reason, {:not_connected, _reason}) do
    :ok
    Logger.info("Stopped LDAP, state was not connected")
  end

  @impl GenServer
  def terminate(_shutdown_reason, ldap_conn) do
    :eldap.close(ldap_conn)
    Logger.info("Stopped LDAP")
  end

  @spec handle_call(
          {:authenticate, charlist, charlist}
          | {:reconnect, list}
          | {:get, Paddle.Filters.t(), dn, atom}
          | {:get_single, Paddle.Filters.t(), dn, atom}
          | {:add, dn, attributes, atom}
          | {:delete, dn, atom}
          | {:modify, dn, atom, [mod]},
          GenServer.from(),
          ldap_conn
        ) ::
          {:reply, term, ldap_conn}

  @impl GenServer
  def handle_call({:reconnect, opts}, _from, ldap_conn) do
    case ldap_conn do
      {:not_connected, _reason} -> nil
      pid -> :eldap.close(pid)
    end

    Logger.info("Reconnecting")

    case do_connect(opts) do
      {:ok, ldap_conn} -> {:reply, {:ok, :connected}, ldap_conn}
      {:error, reason} -> {:reply, {:error, {:not_connected, reason}}, {:not_connected, reason}}
    end
  end

  @impl GenServer
  def handle_call(_message, _from, {:not_connected, _reason} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl GenServer
  def handle_call({:authenticate, dn, password}, _from, ldap_conn) do
    Logger.debug("Authenticating with dn: #{dn}")
    status = :eldap.simple_bind(ldap_conn, dn, password)

    case status do
      :ok -> {:reply, status, ldap_conn}
      {:error, _} -> {:reply, status, ldap_conn}
    end
  end

  @impl GenServer
  def handle_call({:get, filter, kwdn, base}, _from, ldap_conn) do
    base = config(base)
    dn = Parsing.construct_dn(kwdn, base)
    filter = Filters.construct_filter(filter)

    Logger.debug("Getting entries with dn: #{dn} and filter: #{inspect(filter, pretty: true)}")

    {:reply,
     :eldap.search(ldap_conn, base: dn, filter: filter)
     |> Parsing.clean_eldap_search_results(base), ldap_conn}
  end

  @impl GenServer
  def handle_call({:get_single, filter, kwdn, base}, _from, ldap_conn) do
    base = config(base)
    dn = Parsing.construct_dn(kwdn, base)
    filter = Filters.construct_filter(filter)

    Logger.debug(
      "Getting single entry with dn: #{dn} and filter: #{inspect(filter, pretty: true)}"
    )

    {:reply,
     :eldap.search(ldap_conn,
       base: dn,
       scope: :eldap.baseObject(),
       filter: filter
     )
     |> Parsing.clean_eldap_search_results(base)
     |> ensure_single_result, ldap_conn}
  end

  @impl GenServer
  def handle_call({:add, kwdn, attributes, base}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, config(base))

    Logger.info("Adding entry with dn: #{dn}")

    attributes =
      attributes
      |> Enum.filter(fn {_key, value} -> value != nil end)
      |> Enum.map(fn {key, value} -> {'#{key}', Parsing.list_wrap(value)} end)

    {:reply, :eldap.add(ldap_conn, dn, attributes), ldap_conn}
  end

  @impl GenServer
  def handle_call({:delete, kwdn, base}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, config(base))

    Logger.info("Deleting entry with dn: #{dn}")

    {:reply, :eldap.delete(ldap_conn, dn), ldap_conn}
  end

  @impl GenServer
  def handle_call({:modify, kwdn, base, mods}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, config(base))

    Logger.info("Modifying entry: \"#{dn}\" with mods: #{inspect(mods)}")

    mods = mods |> Enum.map(&Parsing.mod_convert/1)

    {:reply, :eldap.modify(ldap_conn, dn, mods), ldap_conn}
  end

  @type authenticate_ldap_error ::
          :operationsError
          | :protocolError
          | :authMethodNotSupported
          | :strongAuthRequired
          | :referral
          | :saslBindInProgress
          | :inappropriateAuthentication
          | :invalidCredentials
          | :unavailable
          | :anonymous_auth
  @spec authenticate(dn, binary) :: :ok | {:error, authenticate_ldap_error}

  @doc ~S"""
  Check the given credentials and authenticate the current connection.

  When given the wrong credentials, returns `{:error, :invalidCredentials}`

  The user id can be passed as a binary, which will expand to
  `<account_identifier>=<id>,<account subdn>,<base>`, or with a keyword list if
  you want to specify the whole DN (but still without the base DN).

  Example:

      iex> Paddle.authenticate("testuser", "test")
      :ok
      iex> Paddle.authenticate("testuser", "wrong password")
      {:error, :invalidCredentials}
      iex> Paddle.authenticate([cn: "admin"], "test")
      :ok
  """
  def authenticate(kwdn, password) when is_list(kwdn) do
    dn = Parsing.construct_dn(kwdn, config(:base))
    GenServer.call(Paddle, {:authenticate, dn, :binary.bin_to_list(password)})
  end

  def authenticate(username, password) do
    dn = Parsing.construct_dn([{config(:account_identifier), username}], config(:account_base))
    GenServer.call(Paddle, {:authenticate, dn, :binary.bin_to_list(password)})
  end

  @doc ~S"""
  Closes the current connection and opens a new one.

  Accepts connection information as arguments.
  Not specified values will be fetched from the config.

  Example:

      iex> Paddle.reconnect(host: ['example.com'])
      {:error, {:not_connected, "connect failed"}}
      iex> Paddle.reconnect()
      {:ok, :connected}
  """
  def reconnect(opts \\ []) do
    GenServer.call(Paddle, {:reconnect, opts})
  end

  @spec get_dn(Paddle.Class.t()) :: {:ok, binary} | {:error, :missing_unique_identifier}

  @doc ~S"""
  Get the DN of an entry.

  Example:

      iex> Paddle.get_dn(%MyApp.PosixAccount{uid: "testuser"})
      {:ok, "uid=testuser,ou=People"}
  """
  def get_dn(object) do
    subdn = Paddle.Class.location(object)

    id_field = Paddle.Class.unique_identifier(object)
    id_value = Map.get(object, id_field)

    if id_value do
      id_value = Paddle.Parsing.ldap_escape(id_value)

      {:ok, "#{id_field}=#{id_value},#{subdn}"}
    else
      {:error, :missing_unique_identifier}
    end
  end

  # =============
  # == Getting ==
  # =============

  @type search_ldap_error ::
          :noSuchObject
          | :sizeLimitExceeded
          | :timeLimitExceeded
          | :undefinedAttributeType
          | :insufficientAccessRights

  @spec get(dn) :: {:ok, [ldap_entry]} | {:error, search_ldap_error}

  @doc ~S"""
  Get one or more LDAP entries given a partial DN and a filter.

  Example:

      iex> Paddle.get(base: [uid: "testuser", ou: "People"])
      {:ok,
       [%{"cn" => ["Test User"],
         "dn" => "uid=testuser,ou=People",
         "gecos" => ["Test User,,,,"], "gidNumber" => ["120"],
         "homeDirectory" => ["/home/testuser"],
         "loginShell" => ["/bin/bash"],
         "objectClass" => ["account", "posixAccount", "top"],
         "uid" => ["testuser"], "uidNumber" => ["500"],
         "userPassword" => ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}]}

      iex> Paddle.get(base: "uid=testuser,ou=People")
      {:ok,
       [%{"cn" => ["Test User"],
         "dn" => "uid=testuser,ou=People",
         "gecos" => ["Test User,,,,"], "gidNumber" => ["120"],
         "homeDirectory" => ["/home/testuser"],
         "loginShell" => ["/bin/bash"],
         "objectClass" => ["account", "posixAccount", "top"],
         "uid" => ["testuser"], "uidNumber" => ["500"],
         "userPassword" => ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}]}

      iex> Paddle.get(base: [uid: "nothing"])
      {:error, :noSuchObject}

      iex> Paddle.get(filter: [uid: "testuser"], base: [ou: "People"])
      {:ok,
       [%{"cn" => ["Test User"],
         "dn" => "uid=testuser,ou=People",
         "gecos" => ["Test User,,,,"], "gidNumber" => ["120"],
         "homeDirectory" => ["/home/testuser"],
         "loginShell" => ["/bin/bash"],
         "objectClass" => ["account", "posixAccount", "top"],
         "uid" => ["testuser"], "uidNumber" => ["500"],
         "userPassword" => ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}]}
  """
  def get(kwdn) when is_list(kwdn) do
    GenServer.call(
      Paddle,
      {:get, Keyword.get(kwdn, :filter), Keyword.get(kwdn, :base), :base}
    )
  end

  @spec get(Paddle.Class.t()) :: {:ok, [Paddle.Class.t()]} | {:error, search_ldap_error}
  @spec get(Paddle.Class.t(), Paddle.Filters.t()) ::
          {:ok, [Paddle.Class.t()]} | {:error, search_ldap_error}

  @doc ~S"""
  Get an entry in the LDAP given a class object. You can specify an optional
  additional filter as second argument.

  Example:

      iex> Paddle.get(%MyApp.PosixAccount{})
      {:ok,
       [%MyApp.PosixAccount{cn: ["Test User"], description: nil,
         gecos: ["Test User,,,,"], gidNumber: ["120"],
         homeDirectory: ["/home/testuser"], host: nil, l: nil,
         loginShell: ["/bin/bash"], o: nil,
         ou: nil, seeAlso: nil, uid: ["testuser"],
         uidNumber: ["500"],
         userPassword: ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}]}

      iex> Paddle.get(%MyApp.PosixGroup{cn: "users"})
      {:ok,
       [%MyApp.PosixGroup{cn: ["users"], description: nil, gidNumber: ["2"],
         memberUid: ["testuser"], userPassword: nil}]}

      iex> Paddle.get(%MyApp.PosixGroup{}, :eldap.substrings('cn', initial: 'a'))
      {:ok,
       [%MyApp.PosixGroup{cn: ["adm"], description: nil, gidNumber: ["3"],
         memberUid: nil, userPassword: nil}]}
  """
  def get(object, additional_filter \\ nil) when is_map(object) do
    fields_filter =
      object
      |> Map.from_struct()
      |> Enum.filter(fn {_key, value} -> value != nil end)

    filter =
      object
      |> Paddle.Class.object_classes()
      |> Filters.class_filter()
      |> Filters.merge_filter(fields_filter)
      |> Filters.merge_filter(additional_filter)

    location = Paddle.Class.location(object)

    with {:ok, entries} <- GenServer.call(Paddle, {:get, filter, location, :base}) do
      {:ok,
       entries
       |> Enum.map(&Parsing.entry_to_class_object(&1, object))}
    end
  end

  @spec get!(dn) :: [ldap_entry]

  @doc ~S"""
  Same as `get/1` but throws in case of an error.
  """
  def get!(kwdn) when is_list(kwdn) do
    {:ok, result} = get(kwdn)
    result
  end

  @spec get!(Paddle.Class.t()) :: [Paddle.Class.t()]
  @spec get!(Paddle.Class.t(), Paddle.Filters.t()) :: [Paddle.Class.t()]

  @doc ~S"""
  Same as `get/2` but throws in case of an error.
  """
  def get!(object, additional_filter \\ []) do
    {:ok, result} = get(object, additional_filter)
    result
  end

  @spec get_single(dn) :: {:ok, ldap_entry} | {:error, search_ldap_error}

  @doc ~S"""
  Get a single LDAP entry given an optional partial DN and an optional filter.

  Example:

      iex> Paddle.get_single(base: [ou: "People"])
      {:ok,
       %{"dn" => "ou=People",
        "objectClass" => ["top", "organizationalUnit"], "ou" => ["People"]}}

      iex> Paddle.get_single(filter: [uid: "nothing"])
      {:error, :noSuchObject}
  """
  def get_single(kwdn) do
    GenServer.call(
      Paddle,
      {:get_single, Keyword.get(kwdn, :filter), Keyword.get(kwdn, :base), :base}
    )
  end

  # ============
  # == Adding ==
  # ============

  @type attributes :: keyword | %{required(binary) => binary} | [{binary, binary}]
  @type add_ldap_error ::
          :undefinedAttributeType
          | :objectClassViolation
          | :invalidAttributeSyntax
          | :noSuchObject
          | :insufficientAccessRights
          | :entryAlreadyExists

  @spec add(dn, attributes) :: :ok | {:error, add_ldap_error}

  @doc ~S"""
  Add an entry to the LDAP given a DN and a list of
  attributes.

  The first argument is the DN given as a string or keyword list. The second
  argument is the list of attributes in the new entry as a keyword list like
  so:

      [objectClass: ["account", "posixAccount"],
       cn: "User",
       loginShell: "/bin/bash",
       homeDirectory: "/home/user",
       uidNumber: 501,
       gidNumber: 100]

  Please note that due to the limitation of char lists you cannot pass directly
  a char list as an attribute value. But, you can wrap it in an array like
  this: `homeDirectory: ['/home/user']`
  """
  def add(kwdn, attributes), do: GenServer.call(Paddle, {:add, kwdn, attributes, :base})

  @spec add(Paddle.Class.t()) ::
          :ok
          | {:error, :missing_unique_identifier}
          | {:error, :missing_req_attributes, [atom]}
          | {:error, add_ldap_error}

  @doc ~S"""
  Add an entry to the LDAP given a class object.

  Example:

      Paddle.add(%MyApp.PosixAccount{uid: "myUser", cn: "My User", gidNumber: "501", homeDirectory: "/home/myUser"})
  """
  def add(class_object) do
    with {:ok, dn} <- get_dn(class_object),
         {:ok, attributes} <- Attributes.get(class_object) do
      add(dn, attributes)
    end
  end

  # ==============
  # == Deleting ==
  # ==============

  @type delete_ldap_error :: :noSuchObject | :notAllowedOnNonLeaf | :insufficientAccessRights

  @spec delete(Paddle.Class.t() | dn) :: :ok | {:error, delete_ldap_error}

  @doc ~S"""
  Delete a LDAP entry given a DN or a class object.

  Examples:

      Paddle.delete("uid=testuser,ou=People")
      Paddle.delete([uid: "testuser", ou: "People"])
      Paddle.delete(%MyApp.PosixAccount{uid: "testuser"})

  The three examples above do exactly the same thing (provided that the
  `MyApp.PosixAccount` is configured appropriately).
  """
  def delete(kwdn) when is_list(kwdn) or is_binary(kwdn) do
    GenServer.call(Paddle, {:delete, kwdn, :base})
  end

  def delete(class_object) when is_map(class_object) do
    with {:ok, dn} <- get_dn(class_object) do
      GenServer.call(Paddle, {:delete, dn, :base})
    end
  end

  # ===============
  # == Modifying ==
  # ===============

  @type mod ::
          {:add, {binary | atom, binary | [binary]}}
          | {:delete, binary}
          | {:replace, {binary | atom, binary | [binary]}}

  @type modify_ldap_error ::
          :noSuchObject
          | :undefinedAttributeType
          | :namingViolation
          | :attributeOrValueExists
          | :invalidAttributeSyntax
          | :notAllowedOnRDN
          | :objectClassViolation
          | :objectClassModsProhibited
          | :insufficientAccessRights

  @spec modify(Paddle.Class.t() | dn, [mod]) :: :ok | {:error, modify_ldap_error}

  @doc ~S"""
  Modify an LDAP entry given a DN or a class object and a list of
  modifications.

  A modification is specified like so:

      {action, {parameters...}}

  Available modifications:

  - `{:add, {field, value}}`
  - `{:delete, field}`
  - `{:replace, {field, value}}`

  For example, adding a "description" field:

      {:add, {"description", "This is a description"}}

  This allows you to do things like this:

      Paddle.modify([uid: "testuser", ou: "People"],
                    add: {"description", "This is a description"},
                    delete: "gecos",
                    replace: {"o", ["Club *Nix", "Linux Foundation"]})

  Or, using class objects:

      Paddle.modify(%MyApp.PosixAccount{uid: "testuser"},
                    add: {"description", "This is a description"},
                    delete: "gecos",
                    replace: {"o", ["Club *Nix", "Linux Foundation"]})

  """
  def modify(kwdn, mods) when is_list(kwdn) or is_binary(kwdn) do
    GenServer.call(Paddle, {:modify, kwdn, :base, mods})
  end

  def modify(class_object, mods) when is_map(class_object) do
    with {:ok, dn} <- get_dn(class_object) do
      GenServer.call(Paddle, {:modify, dn, :base, mods})
    end
  end

  # =======================
  # == Private Utilities ==
  # =======================

  @spec config :: keyword

  @doc ~S"""
  Get the whole configuration of the Paddle application.
  """
  def config, do: Application.get_env(:paddle, Paddle)

  @spec config(atom) :: any

  @doc ~S"""
  Get the environment configuration of the Paddle application under a
  certain key.
  """
  def config(:host) do
    case Keyword.get(config(), :host) do
      host when is_bitstring(host) -> [String.to_charlist(host)]
      hosts when is_list(hosts) -> Enum.map(hosts, &String.to_charlist/1)
    end
  end

  def config(:ssl), do: config(:ssl, false)
  def config(:ipv6), do: config(:ipv6, false)
  def config(:tcpopts), do: config(:tcpopts, [])
  def config(:sslopts), do: config(:sslopts, [])
  def config(:port), do: config(:port, 389)
  def config(:timeout), do: config(:timeout, nil)
  def config(:base), do: config(:base, "") |> :binary.bin_to_list()
  def config(:account_base), do: config(:account_subdn) ++ ',' ++ config(:base)
  def config(:account_subdn), do: config(:account_subdn, "ou=People") |> :binary.bin_to_list()
  def config(:account_identifier), do: config(:account_identifier, :uid)
  def config(:schema_files), do: config(:schema_files, [])

  @spec config(atom, any) :: any

  @doc ~S"""
  Same as `config/1` but allows you to specify a default value.
  """
  def config(key, default), do: Keyword.get(config(), key, default)

  @spec ensure_single_result({:ok, [ldap_entry]} | {:error, atom}) ::
          {:ok, ldap_entry} | {:error, :noSuchObject}

  defp ensure_single_result({:error, error}) do
    case error do
      :noSuchObject -> {:error, :noSuchObject}
    end
  end

  defp ensure_single_result({:ok, []}), do: {:error, :noSuchObject}
  defp ensure_single_result({:ok, [result]}), do: {:ok, result}

  @spec eldap_log_callback(pos_integer, charlist, [term]) :: :ok

  @doc false
  def eldap_log_callback(level, format_string, format_args) do
    message =
      case Application.get_env(:paddle, :filter_passwords, true) do
        true ->
          :io_lib.format(format_string, format_args)
          |> to_string()
          |> String.replace(~r/{simple,".*"}/, ~s({simple,"filtered"}))

        false ->
          :io_lib.format(format_string, format_args)
      end

    case level do
      # Level 1 seems unused by :eldap
      1 -> Logger.info(message)
      2 -> Logger.debug(message)
    end
  end

  defp do_connect(opts) do
    ssl = Keyword.get(opts, :ssl, config(:ssl))
    ipv6 = Keyword.get(opts, :ipv6, config(:ipv6))
    tcpopts = Keyword.get(opts, :tcpopts, config(:tcpopts))
    sslopts = Keyword.get(opts, :sslopts, config(:sslopts))
    host = Keyword.get(opts, :host, config(:host))
    port = Keyword.get(opts, :port, config(:port))
    timeout = Keyword.get(opts, :timeout, config(:timeout))

    Logger.info("Connecting to ldap#{if ssl, do: "s"}://#{inspect(host)}:#{port}")

    tcpopts =
      if ipv6 do
        [:inet6 | tcpopts]
      else
        tcpopts
      end

    options = [ssl: ssl, port: port, tcpopts: tcpopts, log: &eldap_log_callback/3]

    options =
      if timeout do
        Keyword.put(options, :timeout, timeout)
      else
        options
      end

    options =
      if ssl do
        Keyword.put(options, :sslopts, sslopts)
      else
        options
      end

    Logger.debug("Effective :eldap options: #{inspect(options)}")

    case :eldap.open(host, options) do
      {:ok, ldap_conn} ->
        :eldap.controlling_process(ldap_conn, self())
        Logger.info("Connected to LDAP")
        {:ok, ldap_conn}

      {:error, reason} ->
        Logger.info("Failed to connect to LDAP")
        {:error, Kernel.to_string(reason)}
    end
  end
end
