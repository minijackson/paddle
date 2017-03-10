Definitions.

% http://www.rfc-editor.org/rfc/rfc2252.txt
% Section 4.1
% http://www.zytrax.com/books/ldap/apc/rfc4512.txt
% Section 4.1.1

A        = ([a-zA-Z])
D        = ([0-9])
HexDigit = ({D}|[a-fA-F])
K        = ({A}|{D}|\-|;)
P        = ({A}|{D}|\"|\(|\)|\+|,|\-|\.|/|:|?|)
% " <- This quote is here to fix the syntax highlighting in my editor

Letterstring    = ({A}+)
NumericString   = ({D}+)
AnhString       = ({K}+)
KeyString       = ({A}{AnhString}?)
Printablestring = ({P}+)

Whsp            = ([\s\t\n]+)
%DString         = ([a-zA-Z0-9&"\./:;,\(\)\\[\]\{\}#\s\t\c-]+)
DString         = ([^']+)
% ' <- This quote is here to fix the syntax highlighting in my editor
QDString        = ('{DString}')
QDStringList    = ({QDString}*)
QDStrings       = ({QDString}|\({QDStringList}\))

XString = X\-[a-zA-Z_-]+

Descr           = ({KeyString})
QDescr          = ('{Descr}')
Numericoid      = ({NumericString}(\.{NumericString})*)
FakeNumericoid  = ({Descr}:{Numericoid})
WOId            = ({Descr}|{Numericoid})
%OIds            = ({WOId}|\({Whsp}?{OIdList}{Whsp}?\))
OIds            = (\({Whsp}?{WOId}({Whsp}?\${Whsp}?{WOId})*{Whsp}?\))
%OIdList         = ({WOId}({Whsp}?\${Whsp}?{WOId}{Whsp}?)*)
%QDescrs         = ({QDescr}|\({Whsp}?{QDescrList}{Whsp}?\))
QDescrs         = (\(({Whsp}?{QDescr})*{Whsp}?\))
%QDescrList      = (({QDescr})*)

NOIdLen = ({Numericoid}\{{NumericString}\})

AttributeUsage = (userApplications|directoryOperation|distributedOperation|dSAOperation)

DefinitionType = (attribute[tT]ype|object[cC]lass)

%WS         = (\s|\t|\r|\n)
Comment    = (#.*\n)
EmptyLine  = (\n)
%Numericoid = [0-9]+(\.[0-9])*
%DString    = [a-zA-Z0-9\!\#\$\&\.\+\-\^\_]+
%QDString   = '{DString}'

Rules.

\( : {token, {'(', TokenLine}}.
\) : {token, {')', TokenLine}}.

NAME     : {token, {'NAME'    , TokenLine}}.
DESC     : {token, {'DESC'    , TokenLine}}.
OBSOLETE : {token, {'OBSOLETE', TokenLine}}.
SUP      : {token, {'SUP'     , TokenLine}}.

EQUALITY             : {token, {'EQUALITY'            , TokenLine}}.
ORDERING             : {token, {'ORDERING'            , TokenLine}}.
SUBSTR               : {token, {'SUBSTR'              , TokenLine}}.
SYNTAX               : {token, {'SYNTAX'              , TokenLine}}.
SINGLE-VALUE         : {token, {'SINGLE-VALUE'        , TokenLine}}.
COLLECTIVE           : {token, {'COLLECTIVE'          , TokenLine}}.
COLLECTIVE           : {token, {'COLLECTIVE'          , TokenLine}}.
NO-USER-MODIFICATION : {token, {'NO-USER-MODIFICATION', TokenLine}}.
USAGE                : {token, {'USAGE'               , TokenLine}}.

ABSTRACT             : {token, {'ABSTRACT'  , TokenLine}}.
STRUCTURAL           : {token, {'STRUCTURAL', TokenLine}}.
AUXILIARY            : {token, {'AUXILIARY' , TokenLine}}.
MUST                 : {token, {'MUST'      , TokenLine}}.
MAY                  : {token, {'MAY'       , TokenLine}}.

attribute[tT]ype    : {token, {attribute_type, TokenLine}}.
object[cC]lass      : {token, {object_class, TokenLine}}.
object[iI]dentifier : {token, {object_identifier, TokenLine}}.
ldap[sS]yntax       : {token, {ldap_syntax, TokenLine}}.

{AttributeUsage} : {token, {attribute_usage, TokenLine, TokenChars}}.

{XString} : {token, {xstring, TokenLine, TokenChars}}.

{Numericoid} : {token, {numericoid, TokenLine, TokenChars}}.
{FakeNumericoid} : {token, {numericoid, TokenLine, TokenChars}}.
%{Whsp}       : {token, {whsp, TokenLine}}.
{QDescrs}    : {token, {qdescrs, TokenLine, TokenChars}}.
{QDString}   : {token, {qdstring, TokenLine, TokenChars}}.
%{QDStrings}  : {token, {qdstrings, TokenLine, TokenChars}}.
{WOId}       : {token, {woid, TokenLine, TokenChars}}.
{NOIdLen}    : {token, {noidlen, TokenLine, TokenChars}}.
{OIds}       : {token, {oids, TokenLine, TokenChars}}.

{Whsp}      : skip_token.
{Comment}   : skip_token.
{EmptyLine} : skip_token.

Erlang code.
