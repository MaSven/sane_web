defmodule SaneWeb do


  def start() do
    socket= init()
    get_all_devices(socket)
    close(socket)
  end

  def close(socket) do
	  :gen_tcp.close(socket)
  end


  def get_all_devices(socket) do
    send_int(socket,1)
    :gen_tcp.recv(socket,0) |> dbg()

  end




  def init() do
    {:ok, socket} = :gen_tcp.connect('localhost', 45893, [active: false]) |> dbg()
    :gen_tcp.send(socket, 0 |> to_sane_word) |> dbg()
    send_version(socket) |> dbg()
    send_string(socket,"sven") |> dbg()
    :gen_tcp.recv(socket,0) |> dbg()
    socket
  end




  @spec sane_version(integer, integer, integer) :: <<_::32>>
  def sane_version(major, minor, patch) do
    <<major::8,minor::8,0::8,patch::8>>
    # sane_version = Bitwise.&&&(major, 0xFF) |> Bitwise.<<<(24)
    # sane_version = Bitwise.&&&(minor, 0xFF) |> Bitwise.<<<(16) |> Bitwise.|||(sane_version)
    # Bitwise.&&&(patch, 0xFFFF) |> Bitwise.<<<(0) |> Bitwise.|||(sane_version)
  end

  @spec to_sane_word(integer() | binary()) :: binary()
  def to_sane_word(input) when is_integer(input) do
    <<input::32>>
  end

  def to_sane_string(input) when is_binary(input) do
    :unicode.characters_to_binary(input, :unicode,:latin1)
  end

  def send_int(socket, input) do
    :gen_tcp.send(socket, input |> to_sane_word)
  end

  def send_version(socket) do
     :gen_tcp.send(socket,sane_version(1,0,3))
  end

  def send_string(socket, input)  when is_binary(input) do
    sane_string = to_sane_string(input)
    :gen_tcp.send(socket,byte_size(sane_string) |> to_sane_word)
    :gen_tcp.send(socket,sane_string)
    :gen_tcp.send(socket,'')
  end
end
