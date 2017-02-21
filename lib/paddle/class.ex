defprotocol Paddle.Class do
  @moduledoc ~S"""
  Protocol used to allow some objects (mainly structs) to represent an LDAP
  entry.

  Implementing this protocol for your specific classes will enable you to
  manipulate LDAP entries in an easier way than using DNs (hopefully).

  If the class you want to implement is simple enough, you might want to use
  the `Paddle.Class.Helper.gen_class/2` macro.

  For now, only two "classes" implementing this protocol are provided:
  `Paddle.PosixAccount` and `Paddle.PosixGroup`.
  """

  @spec unique_identifier(Paddle.Class) :: atom

  @doc ~S"""
  Return the name of the attribute used in the DN to uniquely identify entries.

  For example, the identifier for an account is `:uid` because an account DN is
  like this: `"uid=testuser,ou=People,..."`
  """
  def unique_identifier(_)

  @spec object_classes(Paddle.Class) :: [binary]

  @doc ~S"""
  Must return the list of classes which this "class" belongs to.

  For example, a posixAccount could have the following object classes:
  `["account", "posixAccount"]`

  The `"top"` class is not required.
  """
  def object_classes(_)

  @spec required_attributes(Paddle.Class) :: [atom]

  @doc ~S"""
  Return the list of required attributes for this "class"

  For example, for the posixAccount class, the following attributes are
  required:

      [:uid, :cn, :uidNumber, :gidNumber, :homeDirectory]
  """
  def required_attributes(_)

  @spec location(Paddle.Class) :: binary | keyword

  @doc ~S"""
  Return the parent subDN (where to add / get entries of this type).

  Example for users: `"ou=People"`

  The top base (e.g. `"dc=organisation,dc=org"`) must not be specified.
  """
  def location(_)

  @spec generators(Paddle.Class) :: [{atom, ((Paddle.Class) -> term)}]

  @doc ~S"""
  Return a list of attributes to be generated using the given functions.

  **Warning:** do not use functions with side effects, as this function may be
  called even if adding a LDAP entry fails.

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

  Example:

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
  Generate a Paddle class represented as a struct with the name `class_name`,
  and the options `options` (see the module toplevel documentation).
  """
  defmacro gen_class(class_name, options) do
    fields              = Keyword.get(options, :fields)
    unique_identifier   = Keyword.get(options, :unique_identifier)
    object_classes      = Keyword.get(options, :object_classes)
    required_attributes = Keyword.get(options, :required_attributes)
    location            = Keyword.get(options, :location)
    generators          = Keyword.get(options, :generators, [])

    quote do
      defmodule unquote(class_name) do
        defstruct unquote(fields)
      end

      defimpl Paddle.Class, for: unquote(class_name) do
        def unique_identifier(_),   do: unquote(unique_identifier)
        def object_classes(_),      do: unquote(object_classes)
        def required_attributes(_), do: unquote(required_attributes)
        def location(_),            do: unquote(location)
        def generators(_),          do: unquote(generators)
      end
    end
  end

end
