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
        group_class: "posixGroup"

  - `:host` - The host of the LDAP server. Mandatory
  - `:base` - The base DN.
  - `:ssl` - When set to `true`, use SSL to connect to the LDAP server.
    Defaults to `false`.
  - `:port` - The port the LDAP server listen to. Defaults to `389`.
  - `:account_subdn` - The DN (without the base) where the accounts are located.
    Defaults to `"ou=People"`.
  - `:group_subdn` - The DN (without the base) where the groups are located.
    Defaults to `"ou=Group"`.
  - `:account_class` - The class (objectClass) of all your user entries.
    Defaults to `"posixAccount"`
  - `:group_class` - The class (objectClass) of all your group entries.
    Defaults to `"posixGroup"`

  ## Usage

  To check a user's credentials, simply do:

      Paddle.check_credentials("username", "password")

  Many functions support passing both a base and a filter via a keyword list
  like so:

      Paddle.get(filter: [uid: "testuser"], base: [ou: "People"])

  You are also provided with some "user" functions that will automatically get
  the information from the right "directory" and check that the entry have the
  right objectClass, see [Configuration](#module-configuration).

  Example:

      Paddle.users(filter: [givenName: "User"])

  ### Filters

  A filter in Paddle is a Keyword list and the atom corresponding to the key
  must have a value strictly equal to, well the given value. When multiple
  keywords are provided, the result must match all criteria.

  If you are missing some filtering capabilities, you can always pass as
  argument an `:eldap` filter like so:

      Paddle.get(filter: :eldap.substrings('uid', initial: 'b'))

  For more informations and examples, see `Paddle.Filters.construct_filter/1`

  ### Bases

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

    if ssl, do: Application.ensure_all_started(:ssl)

    Logger.info("Connecting to ldap#{if ssl, do: "s"}://#{host}:#{port}")

    {:ok, ldap_conn} = :eldap.open([host], ssl: ssl, port: port)
    :eldap.controlling_process(ldap_conn, self)
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
    dn = Parsing.construct_dn([uid: username], config(:account_base))
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

    status = :eldap.add(ldap_conn, dn, attributes)

    {:reply,
     case status do
       :ok -> :ok
       {:error, :undefinedAttributeType} -> {:error, :undefined_attribute_type}
       {:error, :objectClassViolation} -> {:error, :object_class_violation}
     end,
     ldap_conn}
  end

  def handle_call({:delete, kwdn, base}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, config(base))

    {:reply, :eldap.delete(ldap_conn, dn), ldap_conn}
  end

  def handle_call({:modify, kwdn, base, mods}, _from, ldap_conn) do
    dn = Parsing.construct_dn(kwdn, config(base))

    Logger.info("Modifying entry: #{dn} with mods: #{inspect mods}")

    mods = mods |> Enum.map(&Parsing.mod_convert/1)
    Logger.debug("Mods translated in :eldap form: #{inspect mods}")

    {:reply, :eldap.modify(ldap_conn, dn, mods), ldap_conn}
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
      {:ok, "#{id_field}=#{id_value},#{subdn}"}
    else
      {:error, :missing_unique_identifier}
    end
  end

  # =============
  # == Getting ==
  # =============

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

  def get_all(object, additional_filter \\ []) do
    fields_filter = object
             |> Map.from_struct
             |> Enum.filter(fn {_key, value} -> value != nil end)
    filter = Filters.class_filter(Paddle.Class.object_classes(object))
             |> Filters.merge_filter(Filters.construct_filter(fields_filter))
             |> Filters.merge_filter(additional_filter)
    location = Paddle.Class.location(object)
    with {:ok, result} <- GenServer.call(Paddle, {:get, filter, location, :base}) do
      {:ok,
       result
       |> Enum.map(&entry_to_struct(&1, object))}
    end
  end

  def get_all!(object, additional_filter \\ []) do
    {:ok, result} = get_all(object, additional_filter)
    result
  end

  @spec get_single(keyword) :: {:ok, ldap_entry} | {:error, :no_such_object}

  @doc ~S"""
  Get a single LDAP entry given a keyword list.

  Example:

      iex> Paddle.get_single(base: [ou: "People"])
      {:ok,
       %{"dn" => "ou=People,dc=test,dc=com",
        "objectClass" => ["top", "organizationalUnit"], "ou" => ["People"]}}

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

  @spec users(keyword) :: {:ok, [ldap_entry]} | {:error, :no_such_object}

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
                    Filters.class_filter(Keyword.get(kwdn, :filter), ["account", "posixAccount"]),
                    Keyword.get(kwdn, :base),
                    :account_base})
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
                    Filters.class_filter(["account", "posixAccount"]),
                    [uid: uid], :account_base})
  end

  @spec groups() :: {:ok, [ldap_entry]} | {:error, :no_such_object}

  @doc ~S"""
  Get all group entries.

  You can give an additional filter via the `filter:` keyword, but you are not
  allowed to specify the base.

  Example:

      iex> Paddle.groups()
      {:ok,
       [%{"cn" => ["users"], "dn" => "cn=users,ou=Group,dc=test,dc=com",
         "gidNumber" => ["2"], "memberUid" => ["testuser"],
         "objectClass" => ["top", "posixGroup"]},
        %{"cn" => ["adm"], "dn" => "cn=adm,ou=Group,dc=test,dc=com",
         "gidNumber" => ["2"], "objectClass" => ["top", "posixGroup"]}]}
  """
  def groups(kwdn \\ []) do
    GenServer.call(Paddle,
                   {:get,
                    Filters.class_filter(Keyword.get(kwdn, :filter), "posixGroup"),
                    Keyword.get(kwdn, :base),
                    :group_base})
  end

  @spec group(binary | charlist) :: {:ok, ldap_entry} | {:error, :no_such_object}

  @doc ~S"""
  Get a group entry given the group name (cn).

  Example:

      iex> Paddle.group("adm")
      {:ok,
       %{"cn" => ["adm"], "dn" => "cn=adm,ou=Group,dc=test,dc=com",
        "gidNumber" => ["2"], "objectClass" => ["top", "posixGroup"]}}
  """
  def group(cn) do
    GenServer.call(Paddle,
                   {:get_single,
                    Filters.class_filter("posixGroup"),
                    [cn: cn], :group_base})
  end

  @spec users_from_group(binary | charlist) :: {:ok, [ldap_entry]} | {:error, :no_such_object}

  @doc ~S"""
  Get all user entries belonging to a given group (specified by cn)

  Example:

      iex> Paddle.users_from_group("users")
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
  def users_from_group(cn) do
    {:ok, entry} = group(cn)

    filter = entry
             |> Map.fetch!("memberUid")
             |> Enum.map(fn uid -> :eldap.equalityMatch('uid', String.to_charlist(uid)) end)
             |> :eldap.or
    users(filter: filter)
  end

  @spec groups_of_user(binary | charlist) :: {:ok, [ldap_entry]} | {:error, :no_such_object}

  @doc ~S"""
  Get all group entries which a given user belongs to.

  Example:

      iex> Paddle.groups_of_user("testuser")
      {:ok,
       [%{"cn" => ["users"], "dn" => "cn=users,ou=Group,dc=test,dc=com",
         "gidNumber" => ["2"], "memberUid" => ["testuser"],
         "objectClass" => ["top", "posixGroup"]}]}
  """
  def groups_of_user(uid) when is_list(uid), do: groups(filter: :eldap.equalityMatch('memberUid', uid))
  def groups_of_user(uid), do: String.to_charlist(uid) |> groups_of_user

  # ============
  # == Adding ==
  # ============

  @type attributes :: keyword | %{required(binary) => binary} | [{binary, binary}]
  @type add_ldap_error :: {:error, :undefined_attribute_type} | {:error, :object_class_violation}

  @spec add(keyword, attributes) :: :ok | add_ldap_error

  @doc ~S"""
  Add an entry to the LDAP.

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

  Note that even if the above example is about adding a new user, you should
  probably use `add_user/2`.
  """
  def add(kwdn, attributes), do: GenServer.call(Paddle, {:add, kwdn, attributes, :base})

  def add(class_object) do
    with {:ok, dn} <- get_dn(class_object),
         {:ok, attributes} <- Attributes.get(class_object) do
      add(dn, attributes)
    end
  end

  # ==============
  # == Deleting ==
  # ==============

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

  defp config, do: Application.get_env(:paddle, Paddle)

  @spec config(atom) :: any

  defp config(:host),          do: Keyword.get(config, :host)             |> String.to_charlist
  defp config(:ssl),           do: config(:ssl, false)
  defp config(:port),          do: config(:port, 389)
  defp config(:base),          do: config(:base, "")                      |> String.to_charlist
  defp config(:account_base),  do: config(:account_subdn) ++ ',' ++ config(:base)
  defp config(:group_base),    do: config(:group_subdn)   ++ ',' ++ config(:base)
  defp config(:account_subdn), do: config(:account_subdn, "ou=People")    |> String.to_charlist
  defp config(:group_subdn),   do: config(:group_subdn, "ou=Group")       |> String.to_charlist
  defp config(:account_class), do: config(:account_class, "posixAccount") |> String.to_charlist
  defp config(:group_class),   do: config(:group_class, "posixGroup")     |> String.to_charlist

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

  defp entry_to_struct(entry, target) do
    entry = entry
            |> Map.drop(["dn", "objectClass"])
            |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)
            |> Enum.into(%{})

    Map.merge(target, entry)
  end

  @spec ensure_single_result({:ok, [ldap_entry]} | {:error, atom})
  :: {:ok, ldap_entry} | {:error, :no_such_object}

  defp ensure_single_result({:error, error}) do
    case error do
      :no_such_object -> {:error, :no_such_object}
    end
  end

  defp ensure_single_result({:ok, []}), do: {:error, :no_such_object}
  defp ensure_single_result({:ok, [result]}), do: {:ok, result}

end
