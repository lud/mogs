defmodule Mogs.Players.TrackerTest do
  use ExUnit.Case, async: true
  alias Mogs.Players.Tracker

  test "a tracker will exit when its client exits" do
    client =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert {:ok, tracker} = Tracker.start_link(client: client)
    assert Process.alive?(client)
    assert Process.alive?(tracker)

    # We want to try a normal exit but Process.exit(pid, :norma) does
    # not trigger monitors
    send(client, :stop)
    Process.sleep(100)

    assert false == Process.alive?(client)
    assert false == Process.alive?(tracker)
  end

  test "a tracker can be started and monitor players with a timeout" do
    assert {:ok, tracker} = Tracker.start_link(timeout: 1000, client: self())

    spawn_tracked_player = fn id ->
      spawn(fn ->
        assert :ok = Tracker.track(tracker, id, self())
        Process.sleep(:infinity)
      end)
    end

    # Then we will start/kill the player multiple times. As long
    # as a player is re-tracked within the timeout limit, we will
    # receive no message
    for _ <- 1..2 do
      player_1 = spawn_tracked_player.(:p1)
      Process.sleep(100)
      Process.exit(player_1, :kill)
    end

    receive do
      msg -> flunk("Received unexpected message: #{inspect(msg)}")
    after
      990 -> :ok
    end

    assert_receive({Mogs.Players.Tracker, :player_timeout, :p1})
  end
end
