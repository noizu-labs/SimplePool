defmodule Noizu.SimplePool.OptionValue do

  @type t :: %__MODULE__{
    option: atom,
    lookup_key: atom,
    required: boolean,
    default: [atom] | nil,
    valid_values: [any] | :any,
  }

  defstruct [
    option: nil,
    lookup_key: nil,
    required: false,
    default: nil,
    valid_values: :any,
  ]

  defimpl Noizu.OSP, for: Noizu.SimplePool.OptionValue do
    alias Noizu.SimplePool.OptionSettings

    def extract(this, %OptionSettings{} = o) do
      key = this.lookup_key || this.option
      if Keyword.has_key?(o.initial_options, key) do
        arg = o.initial_options[key]
        if this.valid_values == :any do
          %OptionSettings{o| effective_options: Map.put(o.effective_options, this.option, arg)}
        else
          if Enum.member?(this.valid_values, arg) do
            %OptionSettings{o| effective_options: Map.put(o.effective_options, this.option, arg)}
          else
            %OptionSettings{o|
              effective_options: Map.put(o.effective_options, this.option, arg),
              output: %{o.output| errors: Map.put(o.output.errors, this.option, {:unsupported_value, arg})}
            }
          end
        end # ebd if valid_values
      else
        if (this.required) do
          %OptionSettings{o| output: %{o.output| errors: Map.put(o.output.errors, this.option, :required_option_missing)}}
        else
          %OptionSettings{o| effective_options: Map.put(o.effective_options, this.option, this.default)}
        end
      end # end has_key
    end # end def extract

  end # end defimple
end # end defmodule
