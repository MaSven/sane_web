defmodule Sane.Device do
  require Logger
  alias Sane.Socket, as: Socket

  @typedoc """
  Defines the structure of a device given from Sane. This struct is defined in https://sane-project.gitlab.io/standard/1.06/api.html#device-descriptor-type.any()

  This adds the following attributes:
  - is_open defines, if a devices is already open. You can't open a device twice. It would fail with an error.
  - handle is the handle returned from sane for this device, if we opened the device previously.

  All other fields are taken from the sane documentation and have the same meaning.
  """

  defstruct [:name, :vendor, :model, :type, :handle, is_open: false]

  @type t :: %__MODULE__{
          name: binary(),
          vendor: binary(),
          model: binary(),
          type: binary(),
          handle: integer(),
          is_open: boolean()
        }

  @doc """
  Opens this device as specified in https://sane-project.gitlab.io/standard/1.06/net.html#sane-net-open.
  It returns the updated device with the handle inside. If the device is already open, nothing happens. After that, you can use subcalls on this device
  """
  @spec open(:gen_tcp.socket(), Sane.Device.t()) :: {:ok, Sane.Device.t()} | {:error, binary()}
  def open(socket, %Sane.Device{is_open: false} = device) do
    with :ok <- Socket.send_word(socket, 2) |> dbg(),
         :ok <- Socket.send_string(socket, "#{device.name}\0") |> dbg(),
         {:ok, status} <- Socket.recv_word(socket) |> dbg(),
         {:ok, handle} <- Socket.recv_word(socket) |> dbg(),
         {:ok, resource} <- Socket.recv_string(socket),
         :ok <- Socket.map_status_code(status) do
      if resource != "" do
        # authentication needed
      else
        {:ok, %{device | handle: handle, is_open: true}}
      end
    else
      {:error, reason} ->
        Logger.error(
          "Could not activate device #{inspect(device.name)} because of #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  def open(_socket, %Sane.Device{is_open: true} = device), do: {:ok, device}

  @doc """
  Closes this device connections. It means, that other software of connected client to sane can reuse this device.
  If something fails, the is_open sate is untouched
  """
  @spec close(:gent_tcp.socket(),Sane.Device.t()) :: {:ok,Sane.Device.t()} | {:error,binary()}
  def close(socket, %Sane.Device{is_open: true, handle: handle} = device) do
    with :ok <- Socket.send_word(socket, 3),
         :ok <- Socket.send_word(socket, handle) |> dbg(),
         {:ok, _dummy} <- Socket.recv_word(socket) |> dbg do
      {:ok, %{device | is_open: false, handle: nil}}
    else
      {:error, reason} ->
        Logger.error(
          "Could not close device #{inspect(device.name)} because of #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  def close(_socket, %Sane.Device{is_open: false} = device), do: {:ok, device}

  @spec get_all_options_for_device(:gen_tcp.socket,__MODULE__.t()) :: {:ok,}
  def get_all_options_for_device(socket,%__MODULE__{is_open: true,handle: handle}) when is_integer(handle) and !is_nil(handle) do
    with  <- Socket.send_word(socket,4) do

    end
  end




end
