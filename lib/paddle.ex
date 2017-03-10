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
        account_subdn: "ou=People",
        group_subdn: "ou=Group",
        account_class: "inetOrgPerson",
        group_class: "posixGroup",
        schema_files: Path.wildcard("/etc/openldap/schema/*.schema")

  - `:host` -- The host of the LDAP server. Mandatory
  - `:base` -- The base DN.
  - `:ssl` -- When set to `true`, use SSL to connect to the LDAP server.
    Defaults to `false`.
  - `:port` -- The port the LDAP server listen to. Defaults to `389`.
  - `:account_subdn` -- The DN (without the base) where the accounts are located.
    Defaults to `"ou=People"`.
  - `:group_subdn` -- The DN (without the base) where the groups are located.
    Defaults to `"ou=Group"`.
  - `:account_class` -- The class (objectClass) of all your user entries.
    Defaults to `"posixAccount"`
  - `:group_class` -- The class (objectClass) of all your group entries.
    Defaults to `"posixGroup"`
  - `:schema_files` -- Files which are to be parsed to help generate classes
    using
    [`Paddle.Class.Helper`](Paddle.Class.Helper.html#module-using-schema-files).
    Defaults to `[]`.

  ## Usage

  To check a user's credentials and/or authenticate the connection, simply do:

      Paddle.authenticate("username", "password")

  You can also specify the partial DN like so:

      Paddle.authenticate([cn: "admin"], "adminpassword")

  Many functions support passing both a base and a filter via a keyword list
  like so:

      Paddle.get(filter: [uid: "testuser"], base: [ou: "People"])

  But you can also use structs which implements the `Paddle.Class` protocol
  (called [class objects](#module-class-objects)). Some are already defined:

      Paddle.get %Paddle.PosixAccount{uid: "user"}

  The previous example will return every accounts which are in a given subDN
  (defined in the `Paddle.Class` protocol), which have the right objectClass
  (also defined in the same protocol), and have an uid of "user".

  You can also specify an additional [filter](#module-filters) as second
  argument.

  You are also provided with some "user" functions that will automatically get
  the information from the right subDN and check that the entry have the
  right objectClass, see [Configuration](#module-configuration).

  Example:

      Paddle.users(filter: [givenName: "User"])

  ## Class objects

  A class object is simply a struct implementing the `Paddle.Class` protocol.
  Some "classes" are already defined and implemented (see
  `Paddle.PosixAccount`, and `Paddle.PosixGroup`)

  For more informations, see the `Paddle.Class` module documentation.

  ## Filters

  A filter in Paddle is a Keyword list and the atom corresponding to the key
  must have a value strictly equal to, well the given value. When multiple
  keywords are provided, the result must match all criteria.

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

  @type ldap_conn :: :eldap.handle
  @type ldap_entry :: %{required(binary) => binary}
  @type auth_status :: :ok | {:error, atom}

  @type eldap_dn :: charlist
  @type eldap_entry :: {:eldap_entry, eldap_dn, [{charlist, [charlist]}]}

  unless Application.get_env(:paddle, __MODULE__) do
    raise """
    Please configure the LDAP in the config files
    See the `Paddle` module documentation.
    """
  end

  def start(_type, _args) do
    __MODULE__.start_link
  end

  @spec start_link() :: Genserver.on_start

  @doc ~S"""
  Start the LDAP process.

  This function is called by the supervisor handled by the main application
  in `MyApplication.start/2`.
  """
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
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

    Logger.info("Connecting to ldap#{if ssl, do: "s"}://#{host}:#{port}")

    {:ok, ldap_conn} = :eldap.open([host], ssl: ssl, port: port)
    :eldap.controlling_process(ldap_conn, self())
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

  def handle_call({:authenticate, dn, password}, _from, ldap_conn) do
    Logger.debug "Checking credentials with dn: #{dn}"
    status = :eldap.simple_bind(ldap_conn, dn, password)

    case status do
      :ok -> {:reply, status, ldap_conn}
      {:error, :invalidCredentials} -> {:reply, status, ldap_conn}
      {:error, :anonymous_auth} -> {:reply, status, ldap_conn}
    end
  end

  def handle_call({:get, filter, kwdn, base}, _from, ldap_conn) do
    dn     = Parsing.construct_dn(kwdn, config(base))
    filter = Filters.construct_filter(filter)

    Logger.debug("Getting entries with dn: #{dn} and filter: #{inspect filter}")

    {:reply,
     :eldap.search(ldap_conn, base: dn, filter: filter)
     |> clean_eldap_search_results,
     ldap_conn}
  end

  def handle_call({:get_single, filter, kwdn, base}, _from, ldap_conn) do
    dn     = Parsing.construct_dn(kwdn, config(base))
    filter = Filters.construct_filter(filter)

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

  def handle_call({:add, kwdn, attributes, base}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, config(base))

    Logger.info("Adding entry with dn: #{dn}")

    attributes = attributes
                 |> Enum.filter_map(fn {_key, value} -> value != nil end,
                                    fn {key, value} -> {'#{key}', Parsing.list_wrap value} end)

    {:reply, :eldap.add(ldap_conn, dn, attributes), ldap_conn}
  end

  def handle_call({:delete, kwdn, base}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, config(base))

    {:reply, :eldap.delete(ldap_conn, dn), ldap_conn}
  end

  def handle_call({:modify, kwdn, base, mods}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, config(base))

    Logger.info("Modifying entry: \"#{dn}\" with mods: #{inspect mods}")

    mods = mods |> Enum.map(&Parsing.mod_convert/1)
    Logger.debug("Mods translated in :eldap form: #{inspect mods}")

    {:reply, :eldap.modify(ldap_conn, dn, mods), ldap_conn}
  end

  @spec authenticate(keyword | binary, binary) :: boolean

  @doc ~S"""
  Check the given credentials.

  The user id can be given through a binary, which will expand to
  `uid=<id>,<group subdn>,<base>`, or through a keyword list if you want to
  specify the whole DN (still without the base).

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
    GenServer.call(Paddle, {:authenticate, dn, String.to_charlist(password)})
  end

  def authenticate(username, password) do
    dn = Parsing.construct_dn([uid: username], config(:account_base))
    GenServer.call(Paddle, {:authenticate, dn, String.to_charlist(password)})
  end

  @spec get_dn(struct) :: {:ok, binary} | {:error, :missing_unique_identifier}

  @doc ~S"""
  Get the DN of an entry.

  Example:

      iex> Paddle.get_dn(%Paddle.PosixAccount{uid: "testuser"})
      {:ok, "uid=testuser,ou=People"}
  """
  def get_dn(object) do
    subdn = Paddle.Class.location(object)

    id_field = Paddle.Class.unique_identifier(object)
    id_value = Map.get(object, id_field)

    if id_value do
      id_value = Paddle.Parsing.ldap_escape id_value

      {:ok, "#{id_field}=#{id_value},#{subdn}"}
    else
      {:error, :missing_unique_identifier}
    end
  end

  # =============
  # == Getting ==
  # =============

  @type search_ldap_error :: :noSuchObject | :sizeLimitExceeded |
  :timeLimitExceeded | :undefinedAttributeType | :insufficientAccessRights

  @spec get(keyword) :: {:ok, [ldap_entry]} | {:error, search_ldap_error}

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

      iex> Paddle.get(base: "uid=testuser,ou=People")
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
      {:error, :noSuchObject}

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
  def get(kwdn) when is_list(kwdn) do
    GenServer.call(Paddle,
                   {:get,
                    Keyword.get(kwdn, :filter),
                    Keyword.get(kwdn, :base),
                    :base})
  end

  @spec get(Paddle.Class.t, [tuple]) :: {:ok, [Paddle.Class.t]} | {:error, search_ldap_error}

  @doc ~S"""
  Get an entry in the LDAP given a class object. You can specify an optional
  additional filter as second argument.

  Example:

      iex> Paddle.get(%Paddle.PosixAccount{})
      {:ok,
       [%Paddle.PosixAccount{cn: ["Test User"], description: nil,
         gecos: ["Test User,,,,"], gidNumber: ["120"],
         homeDirectory: ["/home/testuser"], host: nil, l: nil,
         loginShell: ["/bin/bash"], o: nil,
         ou: nil, seeAlso: nil, uid: ["testuser"],
         uidNumber: ["500"],
         userPassword: ["{SSHA}AIzygLSXlArhAMzddUriXQxf7UlkqopP"]}]}

      iex> Paddle.get(%Paddle.PosixGroup{cn: "users"})
      {:ok,
       [%Paddle.PosixGroup{cn: ["users"], description: nil, gidNumber: ["2"],
         memberUid: ["testuser"], userPassword: nil}]}

      iex> Paddle.get(%Paddle.PosixGroup{}, :eldap.substrings('cn', initial: 'a'))
      {:ok,
       [%Paddle.PosixGroup{cn: ["adm"], description: nil, gidNumber: ["3"],
         memberUid: nil, userPassword: nil}]}
  """
  def get(object, additional_filter \\ nil) do
    fields_filter = object
             |> Map.from_struct
             |> Enum.filter(fn {_key, value} -> value != nil end)
    filter = Filters.class_filter(Paddle.Class.object_classes(object))
             |> Filters.merge_filter(fields_filter)
             |> Filters.merge_filter(additional_filter)
    location = Paddle.Class.location(object)
    with {:ok, result} <- GenServer.call(Paddle, {:get, filter, location, :base}) do
      {:ok,
       result
       |> Enum.map(&entry_to_struct(&1, object))}
    end
  end

  @spec get!(keyword) :: [ldap_entry]

  @doc ~S"""
  Same as `get/1` but throws in case of an error.
  """
  def get!(kwdn) when is_list(kwdn) do
    {:ok, result} = get(kwdn)
    result
  end

  @spec get!(Paddle.Class.t, [tuple]) :: [Paddle.Class.t]

  @doc ~S"""
  Same as `get/2` but throws in case of an error.
  """
  def get!(object, additional_filter \\ []) do
    {:ok, result} = get(object, additional_filter)
    result
  end

  @spec get_single(keyword) :: {:ok, ldap_entry} | {:error, search_ldap_error}

  @doc ~S"""
  Get a single LDAP entry given a keyword list.

  Example:

      iex> Paddle.get_single(base: [ou: "People"])
      {:ok,
       %{"dn" => "ou=People,dc=test,dc=com",
        "objectClass" => ["top", "organizationalUnit"], "ou" => ["People"]}}

      iex> Paddle.get_single(filter: [uid: "nothing"])
      {:error, :noSuchObject}
  """
  def get_single(kwdn) do
    GenServer.call(Paddle,
                   {:get_single,
                    Keyword.get(kwdn, :filter),
                    Keyword.get(kwdn, :base),
                    :base})
  end

  # ============
  # == Adding ==
  # ============

  @type attributes :: keyword | %{required(binary) => binary} | [{binary, binary}]
  @type add_ldap_error :: :undefinedAttributeType | :objectClassViolation |
  :invalidAttributeSyntax | :noSuchObject | :insufficientAccessRights |
  :entryAlreadyExists

  @spec add(keyword, attributes) :: :ok | {:error, add_ldap_error}

  @doc ~S"""
  Add an entry to the LDAP given a DN and a list of
  attributes.

  The first argument is the DN given as a string or keyword list as usual.
  The second argument is the list of attributes in the new entry as a keyword
  list like so:

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
  def add(kwdn, attributes), do:
    GenServer.call(Paddle, {:add, kwdn, attributes, :base})

  @spec add(Paddle.Class.t) :: :ok | {:error, :missing_unique_identifier} |
  {:error, :missing_req_attributes, [atom]} | {:error, add_ldap_error}

  @doc ~S"""
  Add an entry to the LDAP given a class object.

  Example:

      Paddle.add(%Paddle.PosixAccount{uid: "myUser", cn: "My User", gidNumber: "501", homeDirectory: "/home/myUser"})
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

  @type delete_ldap_error :: :noSuchObject | :notAllowedOnNonLeaf |
  :insufficientAccessRights

  @spec delete(Paddle.Class.t | keyword) :: :ok | {:error, delete_ldap_error}

  @doc ~S"""
  Delete a LDAP entry given a DN or a class object.

  Examples:

      Paddle.delete("uid=testuser,ou=People")
      Paddle.delete([uid: "testuser", ou: "People"])
      Paddle.delete(%Paddle.PosixAccount{uid: "testuser"})

  The three examples above do exactly the same thing (provided that the
  `Paddle.PosixAccount` is configured appropriately).
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

  @type mod :: {:add, {binary | atom, binary | [binary]}} | {:delete, binary} |
  {:replace, {binary | atom, binary | [binary]}}

  @type modify_ldap_error :: :noSuchObject | :undefinedAttributeType |
  :namingViolation | :attributeOrValueExists | :invalidAttributeSyntax |
  :notAllowedOnRDN | :objectClassViolation | :objectClassModsProhibited |
  :insufficientAccessRights

  @spec modify(Paddle.Class.t | keyword, mod) :: :ok | {:error, modify_ldap_error}

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
  Get the environment whole configuration of the Paddle application.
  """
  def config, do: Application.get_env(:paddle, Paddle)

  @spec config(atom) :: any

  @doc ~S"""
  Get the environment configuration of the Paddle application under a
  certain key.
  """
  def config(:host),          do: Keyword.get(config(), :host)           |> String.to_charlist
  def config(:ssl),           do: config(:ssl, false)
  def config(:port),          do: config(:port, 389)
  def config(:base),          do: config(:base, "")                      |> String.to_charlist
  def config(:account_base),  do: config(:account_subdn) ++ ',' ++ config(:base)
  def config(:group_base),    do: config(:group_subdn)   ++ ',' ++ config(:base)
  def config(:account_subdn), do: config(:account_subdn, "ou=People")    |> String.to_charlist
  def config(:group_subdn),   do: config(:group_subdn, "ou=Group")       |> String.to_charlist
  def config(:account_class), do: config(:account_class, "posixAccount") |> String.to_charlist
  def config(:group_class),   do: config(:group_class, "posixGroup")     |> String.to_charlist

  @spec config(atom, any) :: any

  @doc ~S"""
  Same as `config/1` but allows you to specify a default value.
  """
  def config(key, default), do: Keyword.get(config(), key, default)

  @spec clean_eldap_search_results({:ok, {:eldap_search_result, [eldap_entry]}}
                                   | {:error, atom})
  :: {:ok, [ldap_entry]} | {:error, :noSuchObject}

  defp clean_eldap_search_results({:error, error}) do
    case error do
      :noSuchObject -> {:error, :noSuchObject}
    end
  end

  defp clean_eldap_search_results({:ok, {:eldap_search_result, [], []}}) do
    {:error, :noSuchObject}
  end

  defp clean_eldap_search_results({:ok, {:eldap_search_result, entries, []}}) do
    {:ok, Parsing.clean_entries(entries)}
  end

  defp entry_to_struct(entry, target) do
    entry = entry
            |> Map.drop(["dn", "objectClass"])
            |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)
            |> Enum.into(%{})

    Map.merge(target, entry)
  end

  @spec ensure_single_result({:ok, [ldap_entry]} | {:error, atom})
  :: {:ok, ldap_entry} | {:error, :noSuchObject}

  defp ensure_single_result({:error, error}) do
    case error do
      :noSuchObject -> {:error, :noSuchObject}
    end
  end

  defp ensure_single_result({:ok, []}), do: {:error, :noSuchObject}
  defp ensure_single_result({:ok, [result]}), do: {:ok, result}

end
