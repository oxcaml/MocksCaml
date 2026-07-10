AC_PREREQ([2.69])
AC_INIT([MocksCaml],[5.4.0+mock],[https://github.com/oxcaml/MocksCaml/issues])
AC_CONFIG_SRCDIR([src/hello.ml])

dnl Mirrors oxcaml's configure.ac: --enable-runtime5 is accepted (and is the
dnl only supported value); --disable-runtime5 is an error.
AC_ARG_ENABLE([runtime5],
  [AS_HELP_STRING([--enable-runtime5],
    [use the OCaml 5.x runtime (the only supported choice)])],
  [AS_IF([test "x$enableval" != 'xyes'],
    [AC_MSG_ERROR(
      [MocksCaml (like OxCaml 5.4) must be configured with --enable-runtime5])])],
  [])

AC_ARG_ENABLE([dev],
  [AS_HELP_STRING([--enable-dev], [mock dev mode])],
  [enable_dev=$enableval], [enable_dev=no])

AC_ARG_ENABLE([keyword-edition],
  [AS_HELP_STRING([--enable-keyword-edition=VERSION], [mock keyword edition])],
  [keyword_edition=$enableval], [keyword_edition=none])

AC_ARG_ENABLE([warn-error],
  [AS_HELP_STRING([--disable-warn-error],
    [do not treat mock warnings as errors])],
  [warn_error=$enableval], [warn_error=yes])

AC_PROG_CC

AC_PATH_PROG([OCAMLOPT], [ocamlopt], [])
AS_IF([test -z "$OCAMLOPT"],
  [AC_MSG_ERROR([ocamlopt not found in PATH; install OCaml (e.g. via opam) first])])
AC_MSG_NOTICE([using ocamlopt: $OCAMLOPT])

AC_SUBST([enable_dev])
AC_SUBST([keyword_edition])
AC_SUBST([warn_error])

AC_CONFIG_FILES([Makefile.config])
AC_OUTPUT

AC_MSG_NOTICE([MocksCaml configured: dev=$enable_dev keyword_edition=$keyword_edition warn_error=$warn_error])
