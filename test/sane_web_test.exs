defmodule SaneWebTest do
  use ExUnit.Case
  doctest SaneWeb



  test "sane word encoding" do
    assert SaneWeb.sane_version(1,0,3) === <<1,0,0,3>>
  end

  test "sane word encoding binary" do
	 assert SaneWeb.to_sane_string("test")  == "test"
  end
end
