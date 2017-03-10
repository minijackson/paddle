defmodule Paddle.SchemaParser do
  @moduledoc ~S"""
  Module used to parse *.schema files and generate Paddle classes.
  """

  require Logger

  @definitions Application.get_env(:paddle, Paddle)
               |> Keyword.get(:schema_files, [])
               |> Enum.flat_map(fn file ->
                 Logger.info "Loading #{file}"
                 {:ok, lexed, _num} = file
                                      |> File.read!
                                      |> String.to_charlist
                                      |> :schema_lexer.string
                 {:ok, ast} = :schema_parser.parse(lexed)
                 #ast ++ [filename: file]
                 ast
               end)

  defp filter_definitions(definitions, object_classes) when is_list(object_classes) do
    for class <- object_classes do
      filter_definitions(definitions, class)
    end
  end

  defp filter_definitions(definitions, object_class) when is_binary(object_class) do
    definitions
    |> Enum.find(fn {:object_class, defs} ->
      object_class in Keyword.get(defs, :name)
    end)
    |> assert_exists(object_class)
  end

  defp flat_map(enum, fun) when is_list(enum), do: Enum.flat_map(enum, fun)
  defp flat_map(thing, fun), do: fun.(thing)

  defp assert_exists(nil, name), do: raise "Missing objectClass definition: #{name}"
  defp assert_exists(thing, _name), do: thing

  @spec get_fields(binary | [binary]) :: [atom]

  @doc ~S"""
  Get the field names af an object class or a list of object classes.
  """
  def get_fields(object_classes) do
    @definitions
    |> filter_definitions(object_classes)
    |> flat_map(&get_fields_from/1)
  end

  defp get_fields_from({:object_class, description}) do
    mays(description) ++ musts(description)
    |> Enum.map(&String.to_atom/1)
  end

  @spec get_required_attributes(binary | [binary]) :: [atom]

  def get_required_attributes(object_classes) do
    @definitions
    |> filter_definitions(object_classes)
    |> flat_map(&get_required_attributes_from/1)
  end

  defp get_required_attributes_from({:object_class, description}) do
    description
    |> musts
    |> Enum.map(&String.to_atom/1)
  end

  defp mays(description) do
    description
    |> Keyword.get(:may, [])
  end

  defp musts(description) do
    description
    |> Keyword.get(:must, [])
  end

  #defp get_unique_identifier_from({:object_class, description}) do
    #description
    #|> Keyword.get(:must, [])
    #|> hd
  #end

end
