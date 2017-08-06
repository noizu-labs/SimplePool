defmodule Noizu.SimplePool.OptionList do

  @type t :: %__MODULE__{
    option: atom,
    lookup_key: atom,
    required: boolean,
    default: [atom] | nil,
    valid_values: [any] | :any,
    valid_members: [atom] | :any,
    membership_set: boolean
  }

  defstruct [
    option: nil,
    lookup_key: nil,
    required: false,
    default: [],
    valid_values: :any,
    valid_members: :any,
    membership_set: false
  ]

  defimpl Noizu.OSP, for: Noizu.SimplePool.OptionList do
    alias Noizu.SimplePool.OptionSettings

    defp valid_value(arg, this) do
      if this.valid_values == :any do
        :ok
      else
        if Enum.member?(this.valid_values, arg) do
          :ok
        else
          {:error, {:unsupported_value, arg}}
        end
      end # end if valid_values == :any
    end # end valid_values/2

    defp valid_members(arg, this) do
      if this.valid_members == :any do
        :ok
      else
        unsupported = MapSet.difference(MapSet.new(arg), MapSet.new(this.valid_members))
          |> MapSet.to_list()
        if unsupported == [] do
          :ok
        else
          {:error, {:unsupported_members, unsupported}}
        end # end unsupported == []
      end # end this.valid_members == :any0
    end # end valid_members/2

    defp membership_set(arg, this) do
      if this.membership_set do
        List.foldl(this.valid_members, %{}, fn(x,acc) -> Map.put(acc, x, Enum.member?(arg, x)) end)
      else
        arg
      end
    end # end membership_set/2

    def extract(this, %OptionSettings{} = o) do
      key = this.lookup_key || this.option
      if Keyword.has_key?(o.initial_options, key) do
        arg = o.initial_options[key]
        case valid_members(arg, this) do
          :ok ->
            case valid_value(arg, this) do
              :ok ->
                final_arg = membership_set(arg, this)
                %OptionSettings{o| effective_options: Map.put(o.effective_options, this.option, final_arg)}
              {:error, details} ->
                %OptionSettings{o| output: %{o.output| errors: Map.put(o.output.errors, this.option, details)}}
            end
          {:error, details} ->
            %OptionSettings{o| output: %{o.output| errors: Map.put(o.output.errors, this.option, details)}}
        end
      else
        if (this.required) do
          %OptionSettings{o| output: %{o.output| errors: Map.put(o.output.errors, this.option, :required_option_missing)}}
        else
          final_arg = membership_set(this.default, this)
          %OptionSettings{o| effective_options: Map.put(o.effective_options, this.option, final_arg)}
        end
      end
    end # end extract/2
  end # end  defimpl

end # end defmodule
