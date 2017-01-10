defprotocol Paddle.Class do
  @moduledoc ~S"""
  Protocol used to allow some objects (mainly structs) to represent an LDAP
  entry.

  Implementing this protocol for your specific classes will enable you to
  manipulate LDAP entries in an easier way than using DNs (hopefully).

  For now, only two "classes" implementing this protocol are provided:
  `Paddle.PosixAccount` and `Paddle.PosixGroup`.
  """

  @spec unique_identifier(Paddle.Class) :: atom

  @doc ~S"""
  Return the name of the attribute used in the DN to uniquely identify entries.

  For example, the identifier for an account is `:uid` because an account DN is
  like this: `"uid=testuser,ou=People,..."`
  """
  def unique_identifier(_)

  @spec object_classes(Paddle.Class) :: [binary]

  @doc ~S"""
  Must return the list of classes which this "class" belongs to.

  For example, a posixAccount could have the following object classes:
  `["account", "posixAccount"]`

  The `"top"` class is not required.
  """
  def object_classes(_)

  @spec required_attributes(Paddle.Class) :: [atom]

  @doc ~S"""
  Return the list of required attributes for this "class"

  For example, for the posixAccount class, the following attributes are
  required:

      [:uid, :cn, :uidNumber, :gidNumber, :homeDirectory]
  """
  def required_attributes(_)

  @spec location(Paddle.Class) :: binary | keyword

  @doc ~S"""
  Return the parent subDN (where to add / get entries of this type).

  Example for users: `"ou=People"`

  The top base (e.g. `"dc=organisation,dc=org"`) must not be specified.
  """
  def location(_)

  @spec generators(Paddle.Class) :: [{atom, ((Paddle.Class) -> term)}]

  @doc ~S"""
  Return a list of attributes to be generated using the given functions.

  **Warning:** do not use functions with side effects, as this function may be
  called even if adding a LDAP entry fails.

  Example: [uid: &Paddle.PosixAccount.get_next_uid/1]

  This function must take 1 parameter which will be the current class object
  (useful if you have interdependent attribute values) and must return the
  generated value.

  For example, with `%Paddle.PosixGroup{uid: "myUser", ...}` the function will
  be called like this:

      Paddle.PosixAccount.get_next_uid(%Paddle.PosixAccount{uid: "myUser", ...}
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
             :seeAlso, :l, :o, :ou, :host]

  @spec get_next_uid(Paddle.Class.t) :: integer

  @doc ~S"""
  Get a uid for a new user.

  It will get the maximum uidNumber from the users in the current LDAP server
  and increment it by 1.
  """
  def get_next_uid(_) do
    (Paddle.get!(%__MODULE__{})
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

  @spec get_next_gid(Paddle.Class.t) :: integer

  @doc ~S"""
  Get a gid for a new group.

  It will get the maximum gidNumber in the current LDAP server and increment it
  by 1.
  """
  def get_next_gid(_) do
    (Paddle.get!(%__MODULE__{})
     |> Enum.flat_map(&Map.get(&1, :gidNumber))
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
  def generators(_), do: [gidNumber: &Paddle.PosixGroup.get_next_gid/1]
end
