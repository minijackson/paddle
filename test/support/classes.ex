require Paddle.Class.Helper
alias Paddle.Class.Helper

alias MyApp.Class.Generators

Helper.gen_class_from_schema(
  MyApp.PosixAccount,
  ["posixAccount", "account"],
  "ou=People",
  :uid,
  uid: &Generators.get_next_uid/1
)

Helper.gen_class_from_schema(
  MyApp.PosixGroup,
  "posixGroup",
  "ou=Group",
  :cn,
  gidNumber: &Generators.get_next_gid/1
)

defmodule MyApp.Class.Generators do
  @moduledoc ~S"""
  Class used to aggregate the generators of MyApp's provided object classes.
  """

  @spec get_next_uid(Paddle.Class.t()) :: integer

  @doc ~S"""
  Get a uid for a new user.

  It will get the maximum uidNumber from the users in the current LDAP server
  and increment it by 1.
  """
  def get_next_uid(_) do
    (Paddle.get!(%MyApp.PosixAccount{})
     |> Enum.flat_map(&Map.get(&1, :uidNumber))
     |> Enum.map(&String.to_integer/1)
     |> Enum.max()) + 1
  end

  @spec get_next_gid(Paddle.Class.t()) :: integer

  @doc ~S"""
  Get a gid for a new group.

  It will get the maximum gidNumber in the current LDAP server and increment it
  by 1.
  """
  def get_next_gid(_) do
    (Paddle.get!(%MyApp.PosixGroup{})
     |> Enum.flat_map(&Map.get(&1, :gidNumber))
     |> Enum.map(&String.to_integer/1)
     |> Enum.max()) + 1
  end
end

Paddle.Class.Helper.gen_class(MyApp.Room,
  fields: [:cn, :roomNumber, :description, :seeAlso, :telephoneNumber],
  unique_identifier: :cn,
  object_classes: ["room"],
  required_attributes: [:commonName],
  location: "ou=Rooms"
)
