{ stdenv, beamPackages, openldap }:

beamPackages.buildMix {
  name = "paddle";
  version = "0.1.5";

  src = ./.;

  checkInputs = [ openldap ];

  patchPhase = ''
    substituteInPlace .travis/ldap/slapd.conf \
      --replace /etc/ldap ${openldap}/etc \
      --replace /usr/lib/openldap ${openldap}/lib

    cp config/dev.exs config/prod.exs

    substituteInPlace config/test.exs \
      --replace /etc/ldap ${openldap}/etc
  '';

  checkPhase = ''
    mkdir /tmp/slapd
    ${openldap}/libexec/slapd -d2 -f .travis/ldap/slapd.conf -h ldap://localhost:3389 &
    sleep 3
    ldapadd -h localhost:3389 -D cn=admin,dc=test,dc=com -w test -f $src/.travis/ldap/base.ldif
    ldapadd -h localhost:3389 -D cn=admin,dc=test,dc=com -w test -f $src/.travis/ldap/test_data.ldif

    MIX_ENV=test mix test
  '';

  doCheck = true;

  meta = with stdenv.lib; {
    description = "A library simplifying LDAP usage in Elixir projects";
    homepage = "https://github.com/minijackson/paddle";
    license = licenses.mit;
  };
}
