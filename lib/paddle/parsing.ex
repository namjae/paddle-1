defmodule Paddle.Parsing do
  @moduledoc ~S"""
  Module used to parse dn and other LDAP related stuffs.
  """

  # =====================
  # == DN manipulation ==
  # =====================

  @spec construct_dn(keyword | [{binary, binary}], binary | charlist) :: charlist

  @doc ~S"""
  Construct a DN Erlang string based on a keyword list or a string.

  Examples:

      iex> Paddle.Parsing.construct_dn(uid: "user", ou: "People")
      'uid=user,ou=People'

      iex> Paddle.Parsing.construct_dn([{"uid", "user"}, {"ou", "People"}], "dc=organisation,dc=org")
      'uid=user,ou=People,dc=organisation,dc=org'

      iex> Paddle.Parsing.construct_dn("uid=user,ou=People", "dc=organisation,dc=org")
      'uid=user,ou=People,dc=organisation,dc=org'

  Values are escaped.

  Note: using a map is highly discouraged because the key / values may be
  reordered and because they can be mistaken for a class object (see
  `Paddle.Class`).
  """
  def construct_dn(map, base \\ '')

  def construct_dn([], base) when is_list(base), do: base
  def construct_dn([], base), do: String.to_charlist(base)

  def construct_dn(subdn, base) when is_binary(subdn) and is_list(base), do:
    String.to_charlist(subdn) ++ ',' ++ base
  def construct_dn(subdn, base) when is_binary(subdn), do:
    String.to_charlist(subdn) ++ ',' ++ String.to_charlist(base)

  def construct_dn(nil, base) when is_list(base), do: base
  def construct_dn(nil, base), do: String.to_charlist(base)

  def construct_dn(map, '') do
    ',' ++ dn = map
                |> Enum.reduce('', fn {key, value}, acc -> acc ++ ',#{key}=#{ldap_escape value}' end)
    dn
  end

  def construct_dn(map, base) when is_list(base) do
    construct_dn(map, '') ++ ',' ++ base
  end

  def construct_dn(map, base), do: construct_dn(map, String.to_charlist(base))

  @spec dn_to_kwlist(charlist | binary) :: [{binary, binary}]

  @doc ~S"""
  Tranform an LDAP DN to a keyword list.

  Well, not exactly a keyword list but a list like this:

      [{"uid", "user"}, {"ou", "People"}, {"dc", "organisation"}, {"dc", "org"}]

  Example:

      iex> Paddle.Parsing.dn_to_kwlist("uid=user,ou=People,dc=organisation,dc=org")
      [{"uid", "user"}, {"ou", "People"}, {"dc", "organisation"}, {"dc", "org"}]
  """
  def dn_to_kwlist(""), do: []
  def dn_to_kwlist(nil), do: []

  def dn_to_kwlist(dn) when is_binary(dn) do
    %{"key" => key, "value" => value, "rest" => rest} =
      Regex.named_captures(~r/^(?<key>.+)=(?<value>.+)(,(?<rest>.+))?$/U, dn)
    [{key, value}] ++ dn_to_kwlist(rest)
  end

  def dn_to_kwlist(dn), do: dn_to_kwlist(List.to_string(dn))

  @spec ldap_escape(charlist | binary) :: charlist

  @doc ~S"""
  Escape special LDAP characters in a string.

  Example:

      iex> Paddle.Parsing.ldap_escape("a=b#c\\")
      'a\\=b\\#c\\\\'
  """
  def ldap_escape(''), do: ''

  def ldap_escape([char | rest]) do
    escaped_char = case char do
      ?,  -> '\\,'
      ?#  -> '\\#'
      ?+  -> '\\+'
      ?<  -> '\\<'
      ?>  -> '\\>'
      ?;  -> '\\;'
      ?"  -> '\\\"'
      ?=  -> '\\='
      ?\\ -> '\\\\'
      _   -> [char]
    end
    escaped_char ++ ldap_escape(rest)
  end

  def ldap_escape(token), do: ldap_escape(String.to_charlist(token))

  @spec clean_entries([Paddle.eldap_entry]) :: [Paddle.ldap_entry]

  @doc ~S"""
  Get a binary map representation of several eldap entries.

  Example:

      iex> Paddle.Parsing.clean_entries([{:eldap_entry, 'uid=testuser,ou=People', [{'uid', ['testuser']}]}])
      [%{"dn" => "uid=testuser,ou=People", "uid" => ["testuser"]}]
  """
  def clean_entries(entries) do
    entries
    |> Enum.map(&clean_entry/1)
  end

  @spec clean_entry(Paddle.eldap_entry) :: Paddle.ldap_entry

  @doc ~S"""
  Get a binary map representation of a single eldap entry.

  Example:

      iex> Paddle.Parsing.clean_entry({:eldap_entry, 'uid=testuser,ou=People', [{'uid', ['testuser']}]})
      %{"dn" => "uid=testuser,ou=People", "uid" => ["testuser"]}
  """
  def clean_entry({:eldap_entry, dn, attributes}) do
    %{"dn" => List.to_string(dn)}
    |> Map.merge(attributes
                 |> attributes_to_binary
                 |> Enum.into(%{}))
  end

  # ===================
  # == Modifications ==
  # ===================

  @spec mod_convert(Paddle.mod) :: tuple

  @doc ~S"""
  Convert a user-friendly modify operation to an eldap operation.

  Examples:

      iex> Paddle.Parsing.mod_convert {:add, {"description", "This is a description"}}
      {:ModifyRequest_changes_SEQOF, :add,
       {:PartialAttribute, 'description', ['This is a description']}}

      iex> Paddle.Parsing.mod_convert {:delete, "description"}
      {:ModifyRequest_changes_SEQOF, :delete,
       {:PartialAttribute, 'description', []}}

      iex> Paddle.Parsing.mod_convert {:replace, {"description", "This is a description"}}
      {:ModifyRequest_changes_SEQOF, :replace,
       {:PartialAttribute, 'description', ['This is a description']}}
  """
  def mod_convert(operation)

  def mod_convert({:add, {field, value}}) do
    field = '#{field}'
    value = list_wrap value
    :eldap.mod_add(field, value)
  end

  def mod_convert({:delete, field}) do
    field = '#{field}'
    :eldap.mod_delete(field, [])
  end

  def mod_convert({:replace, {field, value}}) do
    field = '#{field}'
    value = list_wrap value
    :eldap.mod_replace(field, value)
  end

  # ===================
  # == Miscellaneous ==
  # ===================

  @spec list_wrap(term) :: [charlist]

  @doc ~S"""
  Wrap things in lists and convert binaries / atoms to charlists.

      iex> Paddle.Parsing.list_wrap "hello"
      ['hello']

      iex> Paddle.Parsing.list_wrap :hello
      ['hello']

      iex> Paddle.Parsing.list_wrap ["hello", "world"]
      ['hello', 'world']
  """
  def list_wrap(list) when is_list(list), do: list |> Enum.map(&'#{&1}')
  def list_wrap(thing), do: ['#{thing}']

  # =======================
  # == Private Utilities ==
  # =======================

  @spec attributes_to_binary([{charlist, [charlist]}]) :: [{binary, [binary]}]

  defp attributes_to_binary(attributes) do
    attributes
    |> Enum.map(&attribute_to_binary/1)
  end

  @spec attribute_to_binary({charlist, [charlist]}) :: {binary, [binary]}

  defp attribute_to_binary({key, values}) do
    {List.to_string(key),
     values |> Enum.map(&List.to_string/1)}
  end

end
