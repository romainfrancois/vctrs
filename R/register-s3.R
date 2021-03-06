# This source code file is licensed under the unlicense license
# https://unlicense.org
#' Register a method for a suggested dependency
#'
#' Generally, the recommend way to register an S3 method is to use the
#' `S3Method()` namespace directive (often generated automatically by the
#' `@export` roxygen2 tag). However, this technique requires that the generic
#' be in an imported package, and sometimes you want to suggest a package,
#' and only provide a method when that package is loaded. `s3_register()`
#' can be called from your package's `.onLoad()` to dynamically register
#' a method only if the generic's package is loaded.
#'
#' For R 3.5.0 and later, `s3_register()` is also useful when demonstrating
#' class creation in a vignette, since method lookup no longer always involves
#' the lexical scope. For R 3.6.0 and later, you can achieve a similar effect
#' by using "delayed method registration", i.e. placing the following in your
#' `NAMESPACE` file:
#'
#' ```
#' if (getRversion() >= "3.6.0") {
#'   S3method(package::generic, class)
#' }
#' ```
#'
#' @section Usage in other packages:
#' To avoid taking a dependency on vctrs, you copy the source of
#' [`s3_register()`](https://github.com/r-lib/vctrs/blob/master/R/register-s3.R)
#' into your own package. It is licensed under the permissive
#' [unlicense](https://choosealicense.com/licenses/unlicense/) to make it
#' crystal clear that we're happy for you to do this. There's no need to include
#' the license or even credit us when using this function.
#'
#' @param generic Name of the generic in the form `pkg::generic`.
#' @param class Name of the class
#' @param method Optionally, the implementation of the method. By default,
#'   this will be found by looking for a function called `generic.class`
#'   in the package environment.
#'
#'   Note that providing `method` can be dangerous if you use
#'   devtools. When the namespace of the method is reloaded by
#'   `devtools::load_all()`, the function will keep inheriting from
#'   the old namespace. This might cause crashes because of dangling
#'   `.Call()` pointers.
#' @export
#' @examples
#' # A typical use case is to dynamically register tibble/pillar methods
#' # for your class. That way you avoid creating a hard dependency on packages
#' # that are not essential, while still providing finer control over
#' # printing when they are used.
#'
#' .onLoad <- function(...) {
#'   s3_register("pillar::pillar_shaft", "vctrs_vctr")
#'   s3_register("tibble::type_sum", "vctrs_vctr")
#' }
#' @keywords internal
# nocov start
s3_register <- function(generic, class, method = NULL) {
  stopifnot(is.character(generic), length(generic) == 1)
  stopifnot(is.character(class), length(class) == 1)

  pieces <- strsplit(generic, "::")[[1]]
  stopifnot(length(pieces) == 2)
  package <- pieces[[1]]
  generic <- pieces[[2]]

  caller <- parent.frame()

  get_method_env <- function() {
    top <- topenv(caller)
    if (isNamespace(top)) {
      asNamespace(environmentName(top))
    } else {
      caller
    }
  }
  get_method <- function(method, env) {
    if (is.null(method)) {
      get(paste0(generic, ".", class), envir = get_method_env())
    } else {
      method
    }
  }

  method_fn <- get_method(method)
  stopifnot(is.function(method_fn))

  # Always register hook in case package is later unloaded & reloaded
  setHook(
    packageEvent(package, "onLoad"),
    function(...) {
      ns <- asNamespace(package)

      # Refresh the method, it might have been updated by `devtools::load_all()`
      method_fn <- get_method(method)

      registerS3method(generic, class, method_fn, envir = ns)
    }
  )

  # Avoid registration failures during loading (pkgload or regular)
  if (!isNamespaceLoaded(package)) {
    return(invisible())
  }

  envir <- asNamespace(package)

  # Only register if generic can be accessed
  if (exists(generic, envir)) {
    registerS3method(generic, class, method_fn, envir = envir)
  }

  invisible()
}

knitr_defer <- function(expr, env = caller_env()) {
  roxy_caller <- detect(sys.frames(), env_inherits, ns_env("knitr"))
  if (is_null(roxy_caller)) {
    abort("Internal error: can't find knitr on the stack.")
  }

  blast(
    withr::defer(!!substitute(expr), !!roxy_caller),
    env
  )
}
blast <- function(expr, env = caller_env()) {
  eval_bare(enexpr(expr), env)
}

knitr_local_registration <- function(generic, class, env = caller_env()) {
  stopifnot(is.character(generic), length(generic) == 1)
  stopifnot(is.character(class), length(class) == 1)

  pieces <- strsplit(generic, "::")[[1]]
  stopifnot(length(pieces) == 2)
  package <- pieces[[1]]
  generic <- pieces[[2]]

  name <- paste0(generic, ".", class)
  method <- env_get(env, name)

  old <- env_bind(global_env(), !!name := method)
  knitr_defer(env_bind(global_env(), !!!old))
}


# nocov end
