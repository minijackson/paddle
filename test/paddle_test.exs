defmodule PaddleTest do
  use ExUnit.Case
  doctest Paddle

  test "class generator helper macro" do
    assert Paddle.get!(%MyApp.Room{})                  == [%MyApp.Room{cn: ["meetingRoom"], description: ["The Room where meetings happens"], roomNumber: ["42"]}]
    assert Paddle.get!(%MyApp.Room{cn: "meetingRoom"}) == [%MyApp.Room{cn: ["meetingRoom"], description: ["The Room where meetings happens"], roomNumber: ["42"]}]
    assert Paddle.get!(%MyApp.Room{roomNumber: 42})    == [%MyApp.Room{cn: ["meetingRoom"], description: ["The Room where meetings happens"], roomNumber: ["42"]}]
  end

end
