# require Paddle.Class.Helper
#
# Paddle.Class.Helper.gen_class(Paddle.Room,
#                               fields: [:cn, :roomNumber, :description,
#                                        :seeAlso, :telephoneNumber],
#                               unique_identifier: :cn,
#                               object_classes: ["room"],
#                               required_attributes: [:commonName],
#                               location: "ou=Rooms")

defmodule PaddleTest do
  use ExUnit.Case
  doctest Paddle

  # test "class generator helper macro" do
  #   assert Paddle.get!(%PaddleTest.Room{})                  == [%PaddleTest.Room{cn: ["meetingRoom"], description: ["The Room where meetings happens"], roomNumber: ["42"]}]
  #   assert Paddle.get!(%PaddleTest.Room{cn: "meetingRoom"}) == [%PaddleTest.Room{cn: ["meetingRoom"], description: ["The Room where meetings happens"], roomNumber: ["42"]}]
  #   assert Paddle.get!(%PaddleTest.Room{roomNumber: 42})    == [%PaddleTest.Room{cn: ["meetingRoom"], description: ["The Room where meetings happens"], roomNumber: ["42"]}]
  # end

end
