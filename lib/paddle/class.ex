defprotocol Paddle.Class do
  @moduledoc ~S"""
  Protocol used to allow some objects (mainly structs) to represent an LDAP
  entry.
  """

  @spec unique_identifier(Paddle.Class) :: atom

  @doc ~S"""
  Return the name of the attribute used in the DN.

  For example, the identifier for a posixAccount is `:uid` because a
  posixAccount DN is like: `"uid=testuser,ou=People,..."`
  """
  def unique_identifier(_)

  @spec object_classes(Paddle.Class) :: [binary]

  @doc ~S"""
  Must return the list of classes which the class belongs to.

  For example, a posixAccount belongs to the object classes:
  `["account", "posixAccount"]`

  The `"top"` class is not required.
  """
  def object_classes(_)

  @spec required_attributes(Paddle.Class) :: [atom]

  @doc ~S"""
  Return the list of required attributes for this objectClass
  """
  def required_attributes(_)

  @spec location(Paddle.Class) :: binary | keyword

  @doc ~S"""
  Return the parent DN (where to add / get entries of this type).

  Example for users: `"ou=People"`

  The top base (e.g. `"dc=organisation,dc=org"`) must not be specified.
  """
  def location(_)

  @spec generators(Paddle.Class) :: [{atom, ((Paddle.Class) -> term)}]

  @doc ~S"""
  Return a list of attributes to be generated using the given functions.

  Example: [uid: &Paddle.PosixAccount.get_next_uid/1]
  """
  def generators(_)
end

defmodule Paddle.PosixAccount do
  @moduledoc ~S"""
  Class representing an account / posixAccount in a LDAP.
  """

  defstruct [# posixAccount
             :uid, :cn, :uidNumber, :gidNumber, :homeDirectory, :userPassword,
             :loginShell, :gecos, :description,
             # account
             :seeAlso, :localityName, :organizationName,
             :organizationalUnitName, :host]

  @doc ~S"""
  Get a uid for a new user.

  It will get the maximum uidNumber from the users in the current LDAP server
  and increment it by 1.
  """
  def get_next_uid(_) do
    (Paddle.get_all!(%__MODULE__{})
     |> Enum.flat_map(&Map.get(&1, :uidNumber))
     |> Enum.map(&String.to_integer/1)
     |> Enum.max) + 1
  end
end

defimpl Paddle.Class, for: Paddle.PosixAccount do
  def unique_identifier(_), do: :uid
  # TODO(minijackson): use config?
  def object_classes(_), do: ["posixAccount", "account"]
  def required_attributes(_), do: [:uid, :cn, :uidNumber, :gidNumber, :homeDirectory]
  # TODO(minijackson): use config.
  def location(_), do: "ou=People"
  def generators(_), do: [uidNumber: &Paddle.PosixAccount.get_next_uid/1]
end

defmodule Paddle.PosixGroup do
  @moduledoc ~S"""
  Class representing a posixGroup in a LDAP.
  """

  defstruct [:cn, :gidNumber, :userPassword, :memberUid, :description]

  @doc ~S"""
  Get a gid for a new group.

  It will get the maximum gidNumber in the current LDAP server and increment it
  by 1.
  """
  def get_next_gid() do
    (Paddle.get_all!(%__MODULE__{})
     |> Enum.flat_map(&Map.get(&1, "gidNumber"))
     |> Enum.map(&String.to_integer/1)
     |> Enum.max) + 1
  end
end

defimpl Paddle.Class, for: Paddle.PosixGroup do
  def unique_identifier(_), do: :cn
  # TODO(minijackson): use config?
  def object_classes(_), do: ["posixGroup"]
  def required_attributes(_), do: [:cn, :gidNumber]
  # TODO(minijackson): use config.
  def location(_), do: "ou=Group"
  def generators(_), do: [uid: &Paddle.PosixGroup.get_next_gid/0]
end
