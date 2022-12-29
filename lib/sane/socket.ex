defmodule Sane.Socket do
  require Logger
  use Agent
  alias Sane.Device, as: Device

  # %{application_name: "sane_test", port: 6566}
  #
  @type recv_array_item_function ::
          (:gen_tcp.socket() -> {:ok, [binary()]} | {:ok, map()} | {:error, binary()})

  @type sane_device :: %{name: binary(), vendor: binary(), model: binary(), type: binary()}

  def start_link(%{port: _port, application_name: _application_name} = init_values) do
    Agent.start_link(fn -> init_values end, name: __MODULE__)
  end

  def connect() do
    Agent.update(__MODULE__, fn %{port: port} = state ->
      case :gen_tcp.connect('localhost', port, active: false) do
        {:ok, socket} ->
          Logger.info("Connection to sane established")
          Map.put(state, :socket, socket)

        {:error, reason} ->
          Logger.warn("Could not establish connection. Because of #{reason}")
      end
    end)
  end

  def get_state() do
    Agent.get(__MODULE__, & &1)
  end

  def initialize_sane() do
    Agent.get(
      __MODULE__,
      fn %{socket: socket, application_name: application_name} ->
        initialize_sane(socket, application_name)
      end,
      :infinity
    )
  end

  def exit_sane() do
    Agent.update(
      __MODULE__,
      fn %{socket: socket} = state ->
        exit_sane(socket)
        %{state | socket: nil}
      end,
      :infinity
    )
  end

  def exit_sane(socket) do
    case send_word(socket, 10) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Could not close connection to sane because of #{reason}")
        :error
    end
  end

  def initialize_sane(socket, application_name) do
    with :ok <- send_word(socket, 0) |> dbg(),
         :ok <- :gen_tcp.send(socket, SaneEncoder.sane_version(1, 0, 3)) |> dbg(),
         :ok <- send_string(socket, application_name) |> dbg(),
         {:ok, packet} <- :gen_tcp.recv(socket, 4) |> dbg(),
         packet = SaneEncoder.from_sane_word(packet),
         {:ok, version} <- :gen_tcp.recv(socket, 4) |> dbg(),
         version = SaneEncoder.from_sane_version(version),
         :ok <- map_status_code(packet) do
      {:ok, version}
    else
      {:error, reason} ->
        Logger.warn("Could not send init because of #{inspect(reason)}")
        {:error, "Init not working"}
    end
  end

  @spec send_word(:gen_tcp.socket(), binary()) :: :ok | {:error, binary()}
  def send_word(socket, word) do
    with encoded_word <- SaneEncoder.to_sane_word(word),
         :ok <- :gen_tcp.send(socket, encoded_word) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec send_string(:gen_tcp.socket(), binary()) :: :ok | {:error, binary()}
  def send_string(socket, string) when is_binary(string) do
    sane_string = SaneEncoder.to_sane_string(string) |> dbg()

    with :ok <- :gen_tcp.send(socket, byte_size(sane_string) |> SaneEncoder.to_sane_word()),
         :ok <- :gen_tcp.send(socket, sane_string),
         :ok <-
           :gen_tcp.send(socket, '') do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def list_all_devices() do
    Agent.get(
      __MODULE__,
      fn %{socket: socket} = _state ->
        list_all_devices(socket)
      end,
      :infinity
    )
  end

  def list_all_devices(socket) do
    with :ok <- send_word(socket, 1),
         {:ok, status} <- recv_word(socket),
         :ok <- map_status_code(status),
         # first word encodes the length of the array
         {:ok, devices} <-
           recv_array(socket, fn socket -> recv_pointer(socket, &recv_sane_device/1) end) do
      {:ok, devices}
    end
  end

  @spec activate_device(Sane.Device.t()) :: {:ok,Device.t()} | {:error,binary()}
  def activate_device(%Device{}=device) do
    Agent.get(__MODULE__, fn state -> Device.open(state.socket, device) end, :infinity)
  end

  def close_device(%Device{}=device) do
    Agent.get(__MODULE__, fn state -> Device.close(state.socket, device) end, :infinity)
  end



  def get_all_options_for_device(handle) when is_integer(handle) do
    Agent.get(__MODULE__,fn state -> get_all_options_for_device(state.socket,handle) end,:infinity)
  end

  def get_all_options_for_device(socket,handle) do
    with :ok  <- send_word(socket,4),
         :ok <- send_word(socket,handle) do
            recv_sane_structure(socket,num_options: &recv_word/1,description: fn socket ->
              recv_pointer(socket,&recv_sane_option_descriptor/1)
            end)
    end
  end

  def recv_sane_option_descriptor(socket) do
    recv_sane_structure(socket,name: &recv_string/1,)
  end

  def recv_word(socket) do
    case :gen_tcp.recv(socket, 4, 10000) do
      {:ok, packet} -> {:ok, SaneEncoder.from_sane_word(packet)}
      {:error, reason} -> {:error, reason}
    end
  end

  def recv_string(socket) do
    with {:ok, string_length} <- :gen_tcp.recv(socket, 4) |> dbg(),
         string_length = SaneEncoder.from_sane_word(string_length) do
      if string_length > 0 do
        case :gen_tcp.recv(socket, string_length) |> dbg() do
          {:ok, string} -> SaneEncoder.from_sane_string(string, string_length)
          {:error, reason} -> {:erro, reason}
        end
      else
        {:ok, ""}
      end
    end
  end

  @spec recv_array_items(
          :gen_tcp.socket(),
          recv_array_item_function(),
          array_length :: non_neg_integer()
        ) :: {:ok, [binary()]} | {:error, reason :: binary()}
  def recv_array_items(socket, recv_item_function, array_length) do
    if array_length > 0 do
      recv_array_item(socket, recv_item_function, array_length, [])
    else
      {:ok, []}
    end
  end

  @spec recv_array(:gen_tcp.socket(), recv_array_item_function()) ::
          {:ok, [binary()]} | {:error, binary()}
  def recv_array(socket, recv_item_function) do
    case recv_word(socket) |> dbg() do
      {:ok, array_length} ->
        array = recv_array_items(socket, recv_item_function, array_length) |> dbg()
        array

      {:error, reason} ->
        Logger.warn("Could not read array because of #{inspect(reason)}")
        {:error, "Could not read array because of #{inspect(reason)}"}
    end
  end

  @spec recv_array_item(:gen_tcp.socket(), recv_array_item_function(), non_neg_integer(), [
          binary()
        ]) ::
          {:ok, items: [binary()]} | {:error, binary()}
  def recv_array_item(socket, recv_item_function, remaining_items, items)
      when remaining_items > 0 and is_list(items) do
    item = recv_item_function.(socket) |> dbg()

    case item do
      {:ok, new_items} ->
        recv_array_item(
          socket,
          recv_item_function,
          remaining_items - 1,
          items ++ List.wrap(new_items)
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  def recv_array_item(_socket, _recv_item_function, 0, items), do: items

  @spec recv_pointer(:gen_tcp.socket(), (:gen_tcp.socket() -> {:ok, map()} | {:error, binary()})) ::
          {:ok, map()} | {:ok, %{}} | {:error, binary()}
  def recv_pointer(socket, recv_pointer_function) do
    case recv_word(socket) |> dbg() do
      {:ok, 0} ->
        recv_pointer_function.(socket) |> dbg()

      {:ok, pointer} when is_integer(pointer) ->
        {:ok, %{}}

      {:error, reason} ->
        Logger.warn("Could not retrieve pointer because of #{inspect(reason)}")
        {:error, "Error while retrieving pointer"}
    end
  end

  @spec recv_sane_device(:gen_tcp.socket()) :: {:ok, sane_device()} | {:error, binary()}
  def recv_sane_device(socket) do
    recv_sane_structure(socket,
      name: &recv_string/1,
      vendor: &recv_string/1,
      model: &recv_string/1,
      type: &recv_string/1
    )
  end

  @spec recv_sane_structure(:gen_tcp.socket(), keyword()) :: {:ok, map()} | {:error, binary()}
  def recv_sane_structure(socket, keywords) do
    require IEx
    IEx.pry()

    structure =
      for {field_name, retrieve_function} <- keywords, into: %{}, uniq: true do
        case retrieve_function.(socket) |> dbg() do
          {:ok, field} ->
            {field_name, field}

          {:error, reason} ->
            Logger.warn(
              "Could not retrieve struct field #{inspect(field_name)} because of #{inspect(reason)}"
            )

            {:error, reason}
        end
      end

    if Map.has_key?(structure, :error) do
      {:error, "Failure while retrieving structure"}
    else
      {:ok, structure}
    end
  end

  @spec map_status_code(0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11) ::
          :ok | {:error, binary()}
  def map_status_code(code) do
    case code do
      0 -> :ok
      1 -> {:error, "Operation is not supported."}
      2 -> {:error, "Operation was cancelled."}
      3 -> {:error, "Device is busy—retry later."}
      4 -> {:error, "Data or argument is invalid."}
      5 -> {:error, "No more data available (end-of-file)."}
      6 -> {:error, "Document feeder jammed."}
      7 -> {:error, "Document feeder out of documents."}
      8 -> {:error, "Scanner cover is open."}
      9 -> {:error, "Error during device I/O."}
      10 -> {:error, "Out of memory."}
      11 -> {:error, "Access to resource has been denied."}
    end
  end
end
