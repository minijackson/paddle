defmodule Paddle.SchemaParser do
  @moduledoc ~S"""
  Module used to parse *.schema files and generate Paddle classes.
  """

  require Logger

  for file <- Paddle.config(:schema_files) do
    @external_resource file
  end

  @definitions Paddle.config(:schema_files)
               |> Enum.flat_map(fn file ->
                 Logger.info("Loading #{file}")

                 {:ok, lexed, _num} =
                   file
                   |> File.read!()
                   |> String.to_charlist()
                   |> :schema_lexer.string()

                 {:ok, ast} = :schema_parser.parse(lexed)
                 ast
               end)

  @object_definitions Enum.filter(
                        @definitions,
                        fn {type, _attrs} -> type == :object_class end
                      )

  @attribute_definitions for(
                           {:attribute_type, attrs} <- @definitions,
                           do: Keyword.get(attrs, :name)
                         ) ++ [["uid", "userid"]]

  @spec attributes(binary | [binary]) :: [atom]

  @doc ~S"""
  Get the attributes names of an object class or a list of object classes.

  Example:

      iex> Paddle.SchemaParser.attributes "account"
      [:description, :seeAlso, :l, :o, :ou, :host, :uid]

      iex> Paddle.SchemaParser.attributes ["posixAccount", "account"]
      [:userPassword, :loginShell, :gecos, :description, :cn, :uid, :uidNumber,
       :gidNumber, :homeDirectory, :seeAlso, :l, :o, :ou, :host]
  """
  def attributes(object_classes) do
    @object_definitions
    |> filter_definitions(object_classes)
    |> Enum.flat_map(&attributes_from/1)
    |> Enum.map(&replace_alias/1)
    |> Enum.map(&String.to_atom/1)
    |> Enum.uniq()
  end

  defp attributes_from({:object_class, description}) do
    mays(description) ++ musts(description)
  end

  @spec required_attributes(binary | [binary]) :: [atom]

  @doc ~S"""
  Get the required attributes names of an object class or a list of object
  classes.

  Example:

      iex> Paddle.SchemaParser.required_attributes "account"
      [:uid]
      iex> Paddle.SchemaParser.required_attributes ["posixAccount", "account"]
      [:cn, :uid, :uidNumber, :gidNumber, :homeDirectory]
  """
  def required_attributes(object_classes) do
    @object_definitions
    |> filter_definitions(object_classes)
    |> Enum.flat_map(&required_attributes_from/1)
    |> Enum.map(&replace_alias/1)
    |> Enum.map(&String.to_atom/1)
    |> Enum.uniq()
  end

  defp required_attributes_from({:object_class, description}) do
    musts(description)
  end

  defp mays(description) do
    description
    |> Keyword.get(:may, [])
  end

  defp musts(description) do
    description
    |> Keyword.get(:must, [])
  end

  defp filter_definitions(definitions, object_class) when is_binary(object_class) do
    filter_definitions(definitions, [object_class])
  end

  defp filter_definitions(definitions, object_classes) when is_list(object_classes) do
    object_classes =
      object_classes
      |> Enum.map(fn class -> {class, :notfound} end)
      |> Enum.into(%{})

    filter_definitions(definitions, object_classes, [])
  end

  defp filter_definitions([], object_classes, filtered) when is_map(object_classes) do
    not_found = for {class, :notfound} <- object_classes, do: class

    case not_found do
      [] -> filtered
      _ -> raise "Missing object classe(s) definition(s): " <> Enum.join(not_found, ", ")
    end
  end

  defp filter_definitions([{:object_class, attrs} = class | rest], object_classes, filtered)
       when is_map(object_classes) do
    name = attrs |> Keyword.get(:name) |> hd

    if Map.has_key?(object_classes, name) do
      if object_classes[name] == :notfound do
        filter_definitions(rest, Map.put(object_classes, name, :found), [class | filtered])
      else
        IO.warn("Multiple definitions of the \"#{name}\" object class", [])
        filter_definitions(rest, object_classes, filtered)
      end
    else
      filter_definitions(rest, object_classes, filtered)
    end
  end

  defp replace_alias(field) do
    Enum.find_value(@attribute_definitions, fn aliases ->
      if field in aliases, do: hd(aliases)
    end) || field
  end
end
