require Paddle.Class.Helper

defmodule Paddle.PosixAccount do
  @moduledoc ~S"""
  Class representing an account / posixAccount in a LDAP.

  Implements the `Paddle.Class` protocol.
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
  @doc false
  def unique_identifier(_), do: :uid
  @doc false
  def object_classes(_), do: ["posixAccount", "account"]
  @doc false
  def required_attributes(_), do: [:uid, :cn, :uidNumber, :gidNumber, :homeDirectory]
  @doc false
  def location(_), do: Paddle.config(:account_subdn) |> List.to_string
  @doc false
  def generators(_), do: [uidNumber: &Paddle.PosixAccount.get_next_uid/1]
end

defmodule Paddle.PosixGroup do
  @moduledoc ~S"""
  Class representing a posixGroup in a LDAP.

  Implements the `Paddle.Class` protocol.
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
  @doc false
  def unique_identifier(_), do: :cn
  @doc false
  def object_classes(_), do: ["posixGroup"]
  @doc false
  def required_attributes(_), do: [:cn, :gidNumber]
  @doc false
  def location(_), do: Paddle.config(:group_subdn) |> List.to_string
  @doc false
  def generators(_), do: [gidNumber: &Paddle.PosixGroup.get_next_gid/1]
end
