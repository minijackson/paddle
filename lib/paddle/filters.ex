defmodule Paddle.Filters do
  @moduledoc ~S"""
  Module used internally by Paddle to manipulate LDAP filters.
  """

  @type easy_filter :: keyword | %{optional(atom | binary) => binary}
  @type eldap_filter :: tuple
  @type filter :: easy_filter | eldap_filter | nil
  @type t :: filter

  @spec construct_filter(filter) :: eldap_filter

  @doc ~S"""
  Construct a eldap filter from the given keyword list or map.

  If given an `:eldap` filter (a tuple), it is returned as is.

  If given `nil`, it will return an empty filter (`:eldap.and([])`).

  Examples:

      iex> Paddle.Filters.construct_filter(uid: "testuser")
      {:equalityMatch, {:AttributeValueAssertion, 'uid', 'testuser'}}

      iex> Paddle.Filters.construct_filter(%{uid: "testuser"})
      {:equalityMatch, {:AttributeValueAssertion, 'uid', 'testuser'}}

      iex> Paddle.Filters.construct_filter(%{"uid" => "testuser"})
      {:equalityMatch, {:AttributeValueAssertion, 'uid', 'testuser'}}

      iex> Paddle.Filters.construct_filter(:eldap.substrings('uid', initial: 'b'))
      {:substrings, {:SubstringFilter, 'uid', [initial: 'b']}}

      iex> Paddle.Filters.construct_filter(nil)
      {:and, []}

      iex> Paddle.Filters.construct_filter([])
      {:and, []}

      iex> Paddle.Filters.construct_filter(uid: "testuser", cn: "Test User")
      {:and,
       [equalityMatch: {:AttributeValueAssertion, 'uid', 'testuser'},
        equalityMatch: {:AttributeValueAssertion, 'cn', 'Test User'}]}
  """
  def construct_filter(filter) when is_tuple(filter), do: filter
  def construct_filter(nil), do: :eldap.and([])

  def construct_filter(filter) when is_map(filter) do
    filter
    |> Enum.into([])
    |> construct_filter()
  end

  def construct_filter([{key, value}]) when is_binary(value) do
    :eldap.equalityMatch('#{key}', '#{value}')
  end

  def construct_filter(kwdn) when is_list(kwdn) do
    criteria =
      kwdn
      |> Enum.map(fn {key, value} -> :eldap.equalityMatch('#{key}', '#{value}') end)

    :eldap.and(criteria)
  end

  @spec merge_filter(filter, filter) :: filter

  @doc ~S"""
  Merge two filters with an "and" operation.

  Examples:

      iex> Paddle.Filters.merge_filter([uid: "testuser"], [cn: "Test User"])
      {:and,
       [equalityMatch: {:AttributeValueAssertion, 'uid', 'testuser'},
        equalityMatch: {:AttributeValueAssertion, 'cn', 'Test User'}]}

      iex> Paddle.Filters.merge_filter([uid: "testuser"], :eldap.substrings('cn', [initial: 'Tes']))
      {:and,
       [equalityMatch: {:AttributeValueAssertion, 'uid', 'testuser'},
        substrings: {:SubstringFilter, 'cn', [initial: 'Tes']}]}

      iex> Paddle.Filters.merge_filter([uid: "testuser"], [])
      [uid: "testuser"]

      iex> Paddle.Filters.merge_filter([], [cn: "Test User"])
      [cn: "Test User"]

      iex> Paddle.Filters.merge_filter([], nil)
      {:and, []}
  """
  def merge_filter(lhs, rhs)

  for lhs <- [[], nil], rhs <- [[], nil] do
    def merge_filter(unquote(lhs), unquote(rhs)), do: :eldap.and([])
  end

  for null_filter <- [[], nil] do
    def merge_filter(filter, unquote(null_filter)), do: filter
    def merge_filter(unquote(null_filter), filter), do: filter
  end

  def merge_filter({:and, lcond}, {:and, rcond}), do: {:and, lcond ++ rcond}
  def merge_filter({:and, lcond}, rhs), do: {:and, [construct_filter(rhs) | lcond]}
  def merge_filter(lhs, {:and, rcond}), do: {:and, [construct_filter(lhs) | rcond]}

  def merge_filter(lhs, rhs) do
    :eldap.and([construct_filter(lhs), construct_filter(rhs)])
  end

  @spec class_filter([binary]) :: eldap_filter

  @doc ~S"""
  Construct a filter that matches a list of objectClasses.

  Examples:

      iex> Paddle.Filters.class_filter ["posixAccount", "account"]
      {:and,
       [equalityMatch: {:AttributeValueAssertion, 'objectClass', 'posixAccount'},
        equalityMatch: {:AttributeValueAssertion, 'objectClass', 'account'}]}
  """
  def class_filter(classes) when is_list(classes) do
    classes
    |> Enum.map(&:eldap.equalityMatch('objectClass', '#{&1}'))
    |> :eldap.and()
  end

  def class_filter(class), do: :eldap.equalityMatch('objectClass', '#{class}')
end
