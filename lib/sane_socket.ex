defmodule SaneSocket do
  require Logger
  use Agent

  # %{application_name: "sane_test", port: 6566}
  #
  @type recv_array_item_function :: (:gen_tcp.socket() -> {:ok, [binary()]} | {:error, binary()})

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

  def send_init() do
    Agent.get(
      __MODULE__,
      fn %{socket: socket, application_name: application_name} ->
        send_init(socket, application_name)
      end,
      :infinity
    )
  end

  def send_init(socket, application_name) do
    with :ok <- :gen_tcp.send(socket, 0 |> SaneEncoder.to_sane_word()) |> dbg(),
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

  def send_string(socket, string) when is_binary(string) do
    sane_string = SaneEncoder.to_sane_string(string)

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
    with :ok <- :gen_tcp.send(socket, 1 |> SaneEncoder.to_sane_word()),
         {:ok, packet} <- :gen_tcp.recv(socket, 4),
         status = SaneEncoder.from_sane_word(packet),
         :ok <- map_status_code(status),
         # first word encodes the length of the array
         {:ok, word_length} <- :gen_tcp.recv(socket, 4),
         word_length = SaneEncoder.from_sane_word(word_length) |> dbg() do
      if word_length > 0 do
        # read rest of bytes to get a clear socket
        recv_string(socket) |> dbg()

        for _index <- 1..word_length do
          # One empty pointer because this is a pointer to pointer to pointer
          with {:ok, name} <- recv_string(socket) |> dbg(),
               {:ok, vendor} <- recv_string(socket) |> dbg(),
               {:ok, model} <- recv_string(socket) |> dbg(),
               {:ok, type} <- recv_string(socket) |> dbg() do
            [name, vendor, model, type]
          end
        end
      end
    end
  end

  def recv_word(socket) do
    case :gen_tcp.recv(socket, 4) do
      {:ok, packet} -> {:ok, SaneEncoder.from_sane_word(packet)}
      {:error, reason} -> {:error, reason}
    end
  end

  def recv_string(socket) do
    with {:ok, string_length} <- :gen_tcp.recv(socket, 4) |> dbg(),
         string_length = SaneEncoder.from_sane_word(string_length) do
      if string_length > 0 do
        case :gen_tcp.recv(socket, string_length) |> dbg() do
          {:ok, string} -> {:ok, :erlang.list_to_binary(string) |> String.graphemes()}
          {:error, reason} -> {:erro, reason}
        end
      end
    end
  end

  @spec recv_array_items(:gen_tcp.socket(), recv_array_item_function(),
          array_length :: non_neg_integer()
        ) :: {:ok, [binary()]} | {:error,reason :: binary()}
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
    case recv_word(socket) do
      {:ok, array_length} ->
        recv_array_items(socket, recv_item_function, array_length)

      {:error, reason} ->
        Logger.warn("Could not read array because of #{inspect(reason)}")
        {:error, "Could not read array because of #{inspect(reason)}"}
    end
  end

  @spec recv_array_item(:gen_tcp.socket(), recv_array_item_function(), non_neg_integer(), [binary()]) ::
          {:ok, items: [binary()]} | {:error, binary()}
  def recv_array_item(socket, recv_item_function, remaining_items, items)
      when remaining_items > 0 do
    case recv_item_function.(socket) do
      {:ok, new_items} ->
        recv_array_item(socket, recv_item_function, remaining_items - 1, items ++ new_items)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def recv_array_item(_socket, _recv_item_function, 0, items), do: items

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
