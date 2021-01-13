defmodule Paddle.Parsing do
  @moduledoc ~S"""
  Module composed of utility functions for translating between `:eldap` and
  `Paddle` representation.
  """

  # =====================
  # == DN manipulation ==
  # =====================

  @spec construct_dn(keyword | [{binary, binary}], binary | charlist) :: charlist

  @doc ~S"""
  Construct a DN Erlang string based on a keyword list or a string.

  Examples:

      iex> Paddle.Parsing.construct_dn(uid: "user", ou: "People")
      'uid=user,ou=People'

      iex> Paddle.Parsing.construct_dn([{"uid", "user"}, {"ou", "People"}], "dc=organisation,dc=org")
      'uid=user,ou=People,dc=organisation,dc=org'

      iex> Paddle.Parsing.construct_dn("uid=user,ou=People", "dc=organisation,dc=org")
      'uid=user,ou=People,dc=organisation,dc=org'

  Values are escaped.

  Note: using a map is highly discouraged because the key / values may be
  reordered and because they can be mistaken for a class object (see
  `Paddle.Class`).
  """
  def construct_dn(subdn, base) when is_binary(base) do
    construct_dn(subdn, :binary.bin_to_list(base))
  end

  def construct_dn(map, base \\ '')

  def construct_dn([], base) when is_list(base), do: base

  def construct_dn(subdn, base) when is_binary(subdn) and is_list(base), do:
    :binary.bin_to_list(subdn) ++ ',' ++ base

  def construct_dn(nil, base) when is_list(base), do: base

  def construct_dn(map, '') do
    ',' ++ dn = Enum.reduce(map,
                            '',
                            fn {key, value}, acc ->
                              acc ++ ',#{key}=#{ldap_escape value}'
                            end)
    dn
  end

  def construct_dn(map, base) when is_list(base) do
    construct_dn(map, '') ++ ',' ++ base
  end

  @spec dn_to_kwlist(charlist | binary) :: [{binary, binary}]

  @doc ~S"""
  Tranform an LDAP DN to a keyword list.

  Well, not exactly a keyword list but a list like this:

      [{"uid", "user"}, {"ou", "People"}, {"dc", "organisation"}, {"dc", "org"}]

  Example:

      iex> Paddle.Parsing.dn_to_kwlist("uid=user,ou=People,dc=organisation,dc=org")
      [{"uid", "user"}, {"ou", "People"}, {"dc", "organisation"}, {"dc", "org"}]
  """
  def dn_to_kwlist(""), do: []
  def dn_to_kwlist(nil), do: []

  def dn_to_kwlist(dn) when is_binary(dn) do
    %{"key" => key, "value" => value, "rest" => rest} =
      Regex.named_captures(~r/^(?<key>.+)=(?<value>.+)(,(?<rest>.+))?$/U, dn)
    [{key, value}] ++ dn_to_kwlist(rest)
  end

  def dn_to_kwlist(dn), do: dn_to_kwlist(List.to_string(dn))

  @spec ldap_escape(charlist | binary) :: charlist

  @doc ~S"""
  Escape special LDAP characters in a string.

  Example:

      iex> Paddle.Parsing.ldap_escape("a=b#c\\")
      'a\\=b\\#c\\\\'
  """
  def ldap_escape(''), do: ''

  def ldap_escape([char | rest]) do
    escaped_char = case char do
      ?,  -> '\\,'
      ?#  -> '\\#'
      ?+  -> '\\+'
      ?<  -> '\\<'
      ?>  -> '\\>'
      ?;  -> '\\;'
      ?"  -> '\\\"'
      ?=  -> '\\='
      ?\\ -> '\\\\'
      _   -> [char]
    end
    escaped_char ++ ldap_escape(rest)
  end

  def ldap_escape(token), do: ldap_escape(:binary.bin_to_list(token))

  # =============
  # == Entries ==
  # =============

  @type eldap_dn :: charlist
  @type eldap_entry :: {:eldap_entry, eldap_dn, [{charlist, [charlist]}]}

  @spec clean_eldap_search_results(
    {:ok, {:eldap_search_result, [eldap_entry]}}
    | {:error, atom},
    charlist
  ) :: {:ok, [Paddle.ldap_entry]} | {:error, Paddle.search_ldap_error}

  @doc ~S"""
  Convert an `:eldap` search result to a `Paddle` representation.

  Also see `clean_entries/1`

  Examples:

      iex> eldap_entry = {:eldap_entry, 'uid=testuser,ou=People', [{'uid', ['testuser']}]}
      iex> Paddle.Parsing.clean_eldap_search_results({:ok, {:eldap_search_result, [eldap_entry], []}}, '')
      {:ok, [%{"dn" => "uid=testuser,ou=People", "uid" => ["testuser"]}]}

      iex> Paddle.Parsing.clean_eldap_search_results({:ok, {:eldap_search_result, [], []}}, '')
      {:error, :noSuchObject}

      iex> Paddle.Parsing.clean_eldap_search_results({:error, :insufficientAccessRights}, '')
      {:error, :insufficientAccessRights}

      iex> eldap_entry = {:eldap_entry, 'uid=testuser,ou=People', [{'uid', ['testuser']}]}
      iex> Paddle.Parsing.clean_eldap_search_results({:ok, {:eldap_search_result, [eldap_entry], []}}, 'ou=People')
      {:ok, [%{"dn" => "uid=testuser", "uid" => ["testuser"]}]}
  """
  def clean_eldap_search_results({:error, error}, _base) do
    {:error, error}
  end

  def clean_eldap_search_results({:ok, {:eldap_search_result, [], []}}, _base) do
    {:error, :noSuchObject}
  end

  def clean_eldap_search_results({:ok, {:eldap_search_result, entries, []}}, base) do
    {:ok, clean_entries(entries, base)}
  end

  @spec entry_to_class_object(Paddle.ldap_entry, Paddle.Class.t) :: Paddle.Class.t

  @doc ~S"""
  Convert a `Paddle` entry to a given `Paddle` class object.

  Example:

      iex> entry = %{"dn" => "uid=testuser,ou=People", "uid" => ["testuser"], "description" => ["hello"]}
      iex> Paddle.Parsing.entry_to_class_object(entry, %MyApp.PosixAccount{})
      %MyApp.PosixAccount{cn: nil, description: ["hello"], gecos: nil,
        gidNumber: nil, homeDirectory: nil, host: nil, l: nil,
        loginShell: nil, o: nil, ou: nil, seeAlso: nil, uid: ["testuser"],
        uidNumber: nil, userPassword: nil}
  """
  def entry_to_class_object(entry, target) do
    entry = entry
            |> Map.drop(["dn", "objectClass"])
            |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)
            |> Enum.into(%{})

    Map.merge(target, entry)
  end

  @spec clean_entries([eldap_entry], charlist) :: [Paddle.ldap_entry]

  @doc ~S"""
  Get a binary map representation of several eldap entries.

  The `base` argument corresponds to the DN base which should be stripped from
  the result's `"dn"` attribute.

  Example:

      iex> Paddle.Parsing.clean_entries([{:eldap_entry, 'uid=testuser,ou=People', [{'uid', ['testuser']}]}], '')
      [%{"dn" => "uid=testuser,ou=People", "uid" => ["testuser"]}]

      iex> Paddle.Parsing.clean_entries([{:eldap_entry, 'uid=testuser,ou=People', [{'uid', ['testuser']}]}], 'ou=People')
      [%{"dn" => "uid=testuser", "uid" => ["testuser"]}]
  """
  def clean_entries(entries, base) do
    base_length = length(base)
    entries
    |> Enum.map(&(clean_entry(&1, base_length)))
  end

  @spec clean_entry(eldap_entry, integer) :: Paddle.ldap_entry

  @doc ~S"""
  Get a binary map representation of a single eldap entry.

  The `base_length` argument corresponds to the DN base length which should be
  stripped from the result's `"dn"` attribute.

  Example:

      iex> Paddle.Parsing.clean_entry({:eldap_entry, 'uid=testuser,ou=People', [{'uid', ['testuser']}]}, 0)
      %{"dn" => "uid=testuser,ou=People", "uid" => ["testuser"]}

      iex> Paddle.Parsing.clean_entry({:eldap_entry, 'uid=testuser,ou=People', [{'uid', ['testuser']}]}, 9)
      %{"dn" => "uid=testuser", "uid" => ["testuser"]}
  """
  def clean_entry({:eldap_entry, dn, attributes}, base_length) do
    %{"dn" => dn |> List.to_string |> strip_base_from_dn(base_length)}
    |> Map.merge(attributes
                 |> attributes_to_binary
                 |> Enum.into(%{}))
  end

  defp strip_base_from_dn(dn, 0) when is_binary(dn), do: dn
  defp strip_base_from_dn(dn, base_length) when is_binary(dn) do
    dn_length = String.length(dn)
    String.slice(dn, 0, dn_length - base_length - 1)
  end

  # ===================
  # == Modifications ==
  # ===================

  @spec mod_convert(Paddle.mod) :: tuple

  @doc ~S"""
  Convert a user-friendly modify operation to an eldap operation.

  Examples:

      iex> Paddle.Parsing.mod_convert {:add, {"description", "This is a description"}}
      {:ModifyRequest_changes_SEQOF, :add,
       {:PartialAttribute, 'description', ['This is a description']}}

      iex> Paddle.Parsing.mod_convert {:delete, "description"}
      {:ModifyRequest_changes_SEQOF, :delete,
       {:PartialAttribute, 'description', []}}

      iex> Paddle.Parsing.mod_convert {:replace, {"description", "This is a description"}}
      {:ModifyRequest_changes_SEQOF, :replace,
       {:PartialAttribute, 'description', ['This is a description']}}
  """
  def mod_convert(operation)

  def mod_convert({:add, {field, value}}) do
    field = '#{field}'
    value = list_wrap value
    :eldap.mod_add(field, value)
  end

  def mod_convert({:delete, field}) do
    field = '#{field}'
    :eldap.mod_delete(field, [])
  end

  def mod_convert({:replace, {field, value}}) do
    field = '#{field}'
    value = list_wrap value
    :eldap.mod_replace(field, value)
  end

  # ===================
  # == Miscellaneous ==
  # ===================

  @spec list_wrap(term) :: [charlist]

  @doc ~S"""
  Wrap things in lists and convert binaries / atoms to charlists.

      iex> Paddle.Parsing.list_wrap "hello"
      ['hello']

      iex> Paddle.Parsing.list_wrap :hello
      ['hello']

      iex> Paddle.Parsing.list_wrap ["hello", "world"]
      ['hello', 'world']
  """
  def list_wrap(list) when is_list(list), do: list |> Enum.map(&:binary.bin_to_list(&1))

  def list_wrap(thing) when is_integer(thing),
    do: [thing |> Integer.to_string() |> :binary.bin_to_list()]

  def list_wrap(thing), do: [:binary.bin_to_list(thing)]

  # =======================
  # == Private Utilities ==
  # =======================

  @spec attributes_to_binary([{charlist, [charlist]}]) :: [{binary, [binary]}]

  defp attributes_to_binary(attributes) do
    attributes
    |> Enum.map(&attribute_to_binary/1)
  end

  @spec attribute_to_binary({charlist, [charlist]}) :: {binary, [binary]}

  defp attribute_to_binary({key, values}) do
    {List.to_string(key),
     values |> Enum.map(&:binary.list_to_bin/1)}
  end

end
