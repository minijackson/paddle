Nonterminals
	schema
	attribute_def attribute_type_description attribute_type_descriptions attribute_type_schema
	object_def object_class_description object_class_descriptions object_class_schema
	syntax_def syntax_schema syntax_descriptions syntax_description
	objectid_def
	name desc obsolete sup
	equality ordering substr syntax single_value collective no_user_modification usage extensions
	kind must may
	real_qdescrs real_noidlen real_oids qdstrings oid
	.

Terminals
	'(' ')'
	'NAME' 'DESC' 'OBSOLETE' 'SUP'
	'EQUALITY' 'ORDERING' 'SUBSTR' 'SYNTAX' 'SINGLE-VALUE' 'COLLECTIVE' 'NO-USER-MODIFICATION' 'USAGE'
	'ABSTRACT' 'STRUCTURAL' 'AUXILIARY' 'MUST' 'MAY'
	attribute_type object_class object_identifier ldap_syntax
	numericoid qdescrs qdstring woid noidlen oids xstring
	attribute_usage
	.

Rootsymbol
	schema.

% ================
% Ambiguous syntax
% ================

% QDescrs can be:
% - 'mystring'                <- like a qstring
% - ( 'mystring' 'mystring')  <- not like a qstring
real_qdescrs -> qdescrs  : split('$1').
real_qdescrs -> qdstring : [unquote('$1')].

% NOIdLen can be:
% - 1.2.3.4.5  <- like a numericoid
% - 1.2.3.4{5} <- not like a numericoid
%
% And, with ldapSyntax, one can define syntax "variables" which are of
% WOId type
real_noidlen -> noidlen.
real_noidlen -> numericoid.
real_noidlen -> woid.

% NOIdLen can be:
% - hello             <- like a woid
% - ( hello $ world ) <- not like a woid
real_oids -> oids : split('$1').
real_oids -> woid : split('$1').

% qdstrings is basically the same thing as qdescrs with some restrictions.
qdstrings -> real_qdescrs.

oid -> woid.
oid -> numericoid.

% ==========
% == Main ==
% ==========

schema -> object_def schema : ['$1' | '$2'].
schema -> attribute_def schema : ['$1' | '$2'].
schema -> objectid_def schema : '$2'.
schema -> syntax_def schema : '$2'.
schema -> '$empty' : [].

object_def    -> object_class object_class_schema     : '$2'.

attribute_def -> attribute_type attribute_type_schema : '$2'.

objectid_def -> object_identifier woid numericoid.

syntax_def -> ldap_syntax syntax_schema.

% ===========================
% == Descriptions for both ==
% ===========================

name       -> 'NAME' real_qdescrs : [{name, '$2'}].
desc       -> 'DESC' qdstring     : [{desc, [unquote('$2')]}].
obsolete   -> 'OBSOLETE'          : [obsolete].
sup        -> 'SUP' real_oids     : [{sup, '$2'}].
extensions -> xstring qdstrings   : [].

% =================================
% == Definitions for objectClass ==
% =================================

kind -> 'ABSTRACT'   : [{kind, kind('$1')}].
kind -> 'STRUCTURAL' : [{kind, kind('$1')}].
kind -> 'AUXILIARY'  : [{kind, kind('$1')}].

must -> 'MUST' real_oids : [{must, '$2'}].
may  -> 'MAY' real_oids  : [{may, '$2'}].

object_class_description -> name       : '$1'.
object_class_description -> desc       : '$1'.
object_class_description -> obsolete   : '$1'.
object_class_description -> sup        : '$1'.
object_class_description -> kind       : '$1'.
object_class_description -> must       : '$1'.
object_class_description -> may        : '$1'.
object_class_description -> extensions : '$1'.

object_class_descriptions ->
	object_class_description object_class_descriptions
	: '$1' ++ '$2'.
object_class_descriptions -> '$empty' : [].

object_class_schema -> '('
	oid
	object_class_descriptions
	')' : {object_class, '$3'}.

% ===================================
% == Definitions for attributeType ==
% ===================================

equality             -> 'EQUALITY' woid         : [].
ordering             -> 'ORDERING' woid         : [].
substr               -> 'SUBSTR' woid           : [].
syntax               -> 'SYNTAX' real_noidlen   : [].
single_value         -> 'SINGLE-VALUE'          : [].
collective           -> 'COLLECTIVE'            : [].
no_user_modification -> 'NO-USER-MODIFICATION'  : [].
usage                -> 'USAGE' attribute_usage : [].

attribute_type_description -> name                 : '$1'.
attribute_type_description -> desc                 : '$1'.
attribute_type_description -> obsolete             : '$1'.
attribute_type_description -> sup                  : '$1'.
attribute_type_description -> equality             : '$1'.
attribute_type_description -> ordering             : '$1'.
attribute_type_description -> substr               : '$1'.
attribute_type_description -> syntax               : '$1'.
attribute_type_description -> single_value         : '$1'.
attribute_type_description -> collective           : '$1'.
attribute_type_description -> no_user_modification : '$1'.
attribute_type_description -> usage                : '$1'.
attribute_type_description -> extensions           : '$1'.

attribute_type_descriptions ->
	attribute_type_description attribute_type_descriptions
	: '$1' ++ '$2'.
attribute_type_descriptions -> '$empty' : [].

attribute_type_schema -> '('
	oid
	attribute_type_descriptions
	')' : {attribute_type, '$3'}.

% ================================
% == Definitions for ldapSyntax ==
% ================================

syntax_description -> name       : '$1'.
syntax_description -> desc       : '$1'.
% Not really an extensions but sufficient for this use-case.
syntax_description -> extensions : '$1'.

syntax_descriptions ->
	syntax_description syntax_descriptions
	: ['$1' | '$2'].
syntax_descriptions -> '$empty' : [].

syntax_schema -> '('
	oid
	syntax_descriptions
	')'.

Erlang code.

unquote({qdstring, _Line, Str}) ->
	unquote(Str);
unquote(Str) ->
	list_to_binary(string:strip(Str, both, $')).

split({woid, _Line, Str}) ->
	[list_to_binary(Str)];
split({qdescrs, _Line, Str}) ->
	lists:map(fun(Str0) -> unquote(Str0) end, string:tokens(Str, " \t\n()"));
split({oids, _Line, Str}) ->
	lists:map(fun(Str0) -> list_to_binary(Str0) end, string:tokens(Str, "$ \t\n()")).

kind({Kind, _Line}) -> Kind.
