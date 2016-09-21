defmodule Paddle.Parsing do
  @moduledoc ~S"""
  Module used to parse dn and other LDAP related stuffs.
  """

  @doc ~S"""
  Construct a DN Erlang string based on a keyword list.

  Use it like this:

      construct_dn(uid: "user", ou: "People")

  Or:

      construct_dn([{"uid", "user"}, {"ou", "People"}], "dc=organisation,dc=org")

  Values are escaped.

  Note: using a map is discouraged because the key / values may be reordered.
  """
  def construct_dn(map, base \\ '')

  def construct_dn(map, '') do
    ',' ++ dn = map
                |> Enum.reduce('', fn {key, value}, acc -> acc ++ ',#{key}=#{ldap_escape value}' end)
    dn
  end

  def construct_dn(map, base) when is_list(base) do
    construct_dn(map, '') ++ ',' ++ base
  end

  def construct_dn(map, base), do: construct_dn(map, String.to_charlist(base))

  @spec dn_to_kwlist(charlist | binary) :: [{binary, binary}]

  @doc ~S"""
  Tranform an LDAP DN to a keyword list.

  Well, not exactly a keyword list but a list like this:

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

  def ldap_escape(token), do: ldap_escape(String.to_charlist(token))

  def clean_entries(entries) do
    entries
    |> Enum.map(&clean_entry/1)
  end

  def clean_entry({:eldap_entry, dn, attributes}) do
    %{"dn" => List.to_string(dn)}
    |> Map.merge(attributes
                 |> attributes_to_binary
                 |> Enum.into(%{}))
  end

  # =======================
  # == Private Utilities ==
  # =======================

  defp attributes_to_binary(attributes) do
    attributes
    |> Enum.map(&attribute_to_binary/1)
  end

  defp attribute_to_binary({key, values}) do
    {List.to_string(key),
     values |> Enum.map(&List.to_string/1)}
  end

end
