
defmodule Noizu.SimplePool.OptionSettings do
  alias Noizu.OSP, as: OptionSettingProtocol
  @type t :: %__MODULE__{
    module: atom,
    option_settings: Map.t,
    initial_options: Map.t,
    effective_options: Map.t,
    output: %{warnings: Map.t, errors: Map.t}
  }

  defstruct [
    module: nil,
    option_settings: %{},
    initial_options: %{},
    effective_options: %{},
    output: %{warnings: %{}, errors: %{}}
  ]

  def expand(%__MODULE__{} = this, options \\ []) do
    this = %__MODULE__{this| initial_options: options}
    Enum.reduce(this.option_settings, this,
      fn({option_name, option_definition}, acc) ->
        OptionSettingProtocol.extract(option_definition, acc)
      end
    )
  end # end expand/2
end
