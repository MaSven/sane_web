defmodule SaneEncoder do

  @type sane_device :: %{
    name: binary(),
    vendor: binary(),
    model: binary(),
    type: binary()
  }

  @spec sane_version(integer(), integer(), integer()) :: binary()
  def sane_version(major, minor, patch) do
    <<major::8, minor::8, 0, patch::8>>
  end

  @spec to_sane_word(integer() | binary()) :: binary()
  def to_sane_word(input) when is_integer(input) do
    <<input::32>>
  end

  def to_sane_word(input) when is_binary(input) do
    :unicode.characters_to_binary(input, :unicode, :latin1)
  end

  @spec to_sane_string(binary()) :: binary()
  def to_sane_string(input) when is_binary(input) do
    :unicode.characters_to_binary(input, :unicode, :latin1)
  end

  @spec from_sane_word([integer()]) :: non_neg_integer()
  def from_sane_word(integers) do
    integers |> :erlang.list_to_binary() |> :binary.decode_unsigned()
  end

  @spec from_sane_version([integer(),...]) :: %{major: integer(),minor: integer(),patch: integer}
  def from_sane_version([major,minor,_,patch]) do
    %{major: major,minor: minor,patch: patch}
  end


end
