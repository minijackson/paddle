defprotocol Paddle.Class do
  @moduledoc ~S"""
  Protocol used to allow some objects (mainly structs) to represent an LDAP
  entry.

  Implementing this protocol for your specific classes will enable you to
  manipulate LDAP entries in an easier way than using DNs (hopefully).

  If the class you want to implement is simple enough, you might want to use
  the `Paddle.Class.Helper.gen_class_from_schema/3` or
  `Paddle.Class.Helper.gen_class/2` macros.

  For now, only two "classes" implementing this protocol are provided:
  `Paddle.PosixAccount` and `Paddle.PosixGroup`.
  """

  @spec unique_identifier(Paddle.Class.t()) :: atom

  @doc ~S"""
  Return the name of the attribute used in the DN to uniquely identify entries.

  For example, the identifier for an account would be `:uid` because an account
  DN would be like: `"uid=testuser,ou=People,..."`
  """
  def unique_identifier(_)

  @spec object_classes(Paddle.Class.t()) :: binary | [binary]

  @doc ~S"""
  Must return the class or the list of classes which this "object class"
  belongs to.

  For example, a posixAccount could have the following object classes:
  `["account", "posixAccount"]`

  The `"top"` class is not required.
  """
  def object_classes(_)

  @spec required_attributes(Paddle.Class.t()) :: [atom]

  @doc ~S"""
  Return the list of required attributes for this "class"

  For example, for the posixAccount class, the following attributes are
  required:

      [:uid, :cn, :uidNumber, :gidNumber, :homeDirectory]
  """
  def required_attributes(_)

  @spec location(Paddle.Class.t()) :: binary | keyword

  @doc ~S"""
  Return the parent subDN (where to add / get entries of this type).

  Example for users: `"ou=People"`

  The top base (e.g. `"dc=organisation,dc=org"`) must not be specified.
  """
  def location(_)

  @spec generators(Paddle.Class.t()) :: [{atom, (Paddle.Class -> term)}]

  @doc ~S"""
  Return a list of attributes to be generated using the given functions.

  **Warning:** do not use functions with side effects, as this function may be
  called even if adding some LDAP entries fails.

  Example: [uid: &Paddle.PosixAccount.get_next_uid/1]

  This function must take 1 parameter which will be the current class object
  (useful if you have interdependent attribute values) and must return the
  generated value.

  For example, with `%Paddle.PosixGroup{uid: "myUser", ...}` the function will
  be called like this:

      Paddle.PosixAccount.get_next_uid(%Paddle.PosixAccount{uid: "myUser", ...}
  """
  def generators(_)
end

defmodule Paddle.Class.Helper do
  @moduledoc ~S"""
  A helper module to help generate paddle classes.

  There is currently two ways of generating paddle classes:

  ## Using schema files

  The simplest way is to find `*.schema` files which contain definitions of
  LDAP object classes. You can find them in the `/etc/(open)ldap/schema/`
  directory if you have OpenLDAP installed. If not, you can find most of them
  [here](https://www.openldap.org/devel/gitweb.cgi?p=openldap.git;a=tree;f=servers/slapd/schema;h=55325b541890a9210178920c78231d2e392b0e39;hb=HEAD).
  Then, add the path of these files in the Paddle configuration using the
  `:schema_files` key (see the [`Paddle`](Paddle.html#module-configuration)
  module toplevel documentation). Finally just call the
  `gen_class_from_schema/3` macro from anywhere outside of a module.

  Example:

      require Paddle.Class.Helper
      Paddle.Class.Helper.gen_class_from_schema MyApp.Room, ["room"], "ou=Rooms"

  For a description of the parameters and more configuration options, see the
  `gen_class_from_schema/3` macro documentation.

  ## Manually describing the class

  If you're feeling more adventurous you can still use this helper you can also
  specify by hand each part of the class using the
  `Paddle.Class.Helper.gen_class/2` macro (if that still doesn't satisfy you,
  you can always look at the `Paddle.Class` protocol).

  Example (which is equivalent to the example above):

      require Paddle.Class.Helper
      Paddle.Class.Helper.gen_class MyApp.Room,
        fields: [:commonName, :roomNumber, :description, :seeAlso, :telephoneNumber],
        unique_identifier: :commonName,
        object_classes: ["room"],
        required_attributes: [:commonName],
        location: "ou=Rooms"

  The available options are all function names defined and documented
  in the `Paddle.Class` protocol, plus the `:fields` option which
  defines all the available fields for the given class.

  Please note that using the `:generators` option here is discouraged
  as generators should be inside the module and not elsewhere. Unless
  you are sure what you are doing is elegant enough, you should define the
  module yourself instead of using this macro with the `:generators` option
  (see the `Paddle.Class` and the source of this macro for guidelines).
  """

  @doc ~S"""
  Generate a Paddle class.

  Generate a Paddle class represented as a struct with the name `class_name`,
  and the options `options` (see [the module toplevel
  documentation](#module-manually-describing-the-class)).
  """
  defmacro gen_class(class_name, options) do
    fields = Keyword.get(options, :fields)
    unique_identifier = Keyword.get(options, :unique_identifier)
    object_classes = Keyword.get(options, :object_classes)
    required_attributes = Keyword.get(options, :required_attributes)
    location = Keyword.get(options, :location)
    generators = Keyword.get(options, :generators, [])

    quote do
      defmodule unquote(class_name) do
        defstruct unquote(fields)
      end

      defimpl Paddle.Class, for: unquote(class_name) do
        def unique_identifier(_), do: unquote(unique_identifier)
        def object_classes(_), do: unquote(object_classes)
        def required_attributes(_), do: unquote(required_attributes)
        def location(_), do: unquote(location)
        def generators(_), do: unquote(generators)
      end
    end
  end

  @doc ~S"""
  Generate a Paddle class from schema files.

  Generate a Paddle class from one of the schema files passed as configuration
  with the name `class_name`, with the given `object_classes` (can be a binary
  or a list of binary), at the given location, optionally force specify
  which field to use as a unique identifier (see
  `Paddle.Class.unique_identifier/1`), and some optional generators (see
  `Paddle.Class.generators/1`)
  """
  defmacro gen_class_from_schema(
             class_name,
             object_classes,
             location,
             unique_identifier \\ nil,
             generators \\ []
           ) do
    {class_name, _bindings} = Code.eval_quoted(class_name, [], __CALLER__)
    {object_classes, _bindings} = Code.eval_quoted(object_classes, [], __CALLER__)
    {location, _bindings} = Code.eval_quoted(location, [], __CALLER__)
    {unique_identifier, _bindings} = Code.eval_quoted(unique_identifier, [], __CALLER__)
    {generators, _bindings} = Code.eval_quoted(generators, [], __CALLER__)

    fields = Paddle.SchemaParser.attributes(object_classes)
    required_attributes = Paddle.SchemaParser.required_attributes(object_classes)
    unique_identifier = unique_identifier || hd(required_attributes)

    quote do
      defmodule unquote(class_name) do
        defstruct unquote(fields)
      end

      defimpl Paddle.Class, for: unquote(class_name) do
        def unique_identifier(_), do: unquote(unique_identifier)
        def object_classes(_), do: unquote(object_classes)
        def required_attributes(_), do: unquote(required_attributes)
        def location(_), do: unquote(location)
        def generators(_), do: unquote(generators)
      end
    end
  end
end
