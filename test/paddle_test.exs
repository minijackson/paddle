defmodule PaddleTest do
  use ExUnit.Case
  doctest Paddle

  test "class generator helper macro" do
    assert Paddle.get!(%MyApp.Room{}) == [
             %MyApp.Room{
               cn: ["ùnícödəR°°m"],
               description: ["The Room where ùnícödə happens 🏰"],
               roomNumber: ["8"]
             },
             %MyApp.Room{
               cn: ["meetingRoom"],
               description: ["The Room where meetings happens"],
               roomNumber: ["42"]
             }
           ]

    assert Paddle.get!(%MyApp.Room{cn: "meetingRoom"}) == [
             %MyApp.Room{
               cn: ["meetingRoom"],
               description: ["The Room where meetings happens"],
               roomNumber: ["42"]
             }
           ]

    assert Paddle.get!(%MyApp.Room{roomNumber: 42}) == [
             %MyApp.Room{
               cn: ["meetingRoom"],
               description: ["The Room where meetings happens"],
               roomNumber: ["42"]
             }
           ]
  end

  test "when a connection cannot be open" do
    Paddle.reconnect(host: ['example.com'])

    assert Paddle.authenticate([cn: "admin"], "password") == {:error, :not_connected}
    assert Paddle.get(base: [uid: "testuser", ou: "People"]) == {:error, :not_connected}

    Paddle.reconnect()
  end
end
