defmodule Sane.Device.Options do

  @moduledoc """
  Defines the structure of the sane_option_descriptor_type https://sane-project.gitlab.io/standard/1.06/api.html#option-descriptor-type
  """

  defstruct [:name, :title, :desc, :type, :unit, :size, :cap, :constraint_type]



  @typedoc """
  Strcture is the representation of the c struct sane option descriptor type.
  """
  @type t :: %__MODULE__{name: binary(), title: binary(), type: sane_option_value_type(),unit: sane_option_unit(),size: integer(),cap: integer()}

  @typedoc """
  `t:sane_option_value_type/0` defines the type of one `Sane.Device.Options.t()`.

  - :sane_bool 0
    Option value is of type SANE_Bool
  - :sane_int 1
    Option value is of type SANE_Int.
  - :sane_fixed 2
    Option value is of type SANE_Fixed.
  - :sane_string 3
    Option value is of type SANE_String.
  - :sane_button 4
    An option of this type has no value. Instead, setting an option of this type has an option-specific side-effect. For example, a button-typed option could be used by a backend to provide a means to select default values or to the tell an automatic document feeder to advance to the next sheet of paper.
  - :sane_group 5
    An option of this type has no value. This type is used to group logically related options. A group option is in effect up to the point where another group option is encountered (or up to the end of the option list, if there are no other group options). For group options, only members title and type are valid in the option descriptor.

  The values after the atom specify how this type is encoded over the wire. As this is a c enum, it is serialized as an integer.
  """
  @type sane_option_value_type ::
          :sane_bool | :sane_int | :sane_fixed | :sane_string | :sane_button | :sane_group
  @typedoc """
  Specifies the unit of the option value.

  - :unit_pixel 0
    Value is unit-less (e.g., page count).
  - :unit_pixel 1
    Value is in number of pixels.
  - :unit_bit 2
    Value is in number of bits.
  - :unit_mm 3
    Value is in millimeters.
  - :unit_dpi 4
    Value is a resolution in dots/inch.
  - :unit_percent 5
    Value is a percentage.
  - :unit_microsecond 6
    Value is time in μ-seconds.

  The integer defines how this type is encoded over the wire. As this is a c enum, it is serialized as an integer.
  """
  @type sane_option_unit ::
          :unit_none
          | :unit_pixel
          | :unit_bit
          | :unit_mm
          | :unit_dpi
          | :unit_percent
          | :unit_microsecond

end
