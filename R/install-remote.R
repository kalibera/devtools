#' Install a remote package.
#'
#' This:
#' \enumerate{
#'   \item downloads source bundle
#'   \item decompresses & checks that it's a package
#'   \item adds metadata to DESCRIPTION
#'   \item calls install
#' }
#' @noRd
install_remote <- function(remote, ..., force = FALSE, quiet = FALSE) {
  stopifnot(is.remote(remote))

  remote_sha <- remote_sha(remote)
  package_name <- remote_package_name(remote)
  local_sha <- local_sha(package_name)

  if (!isTRUE(force) &&
    !different_sha(remote_sha = remote_sha, local_sha = local_sha)) {

    if (!quiet) {
      message(
        "Skipping install of '", package_name, "' from a ", sub("_remote", "", class(remote)[1L]), " remote,",
        " the SHA1 (", substr(remote_sha, 1L, 8L), ") has not changed since last install.\n",
        "  Use `force = TRUE` to force installation")
    }
    return(invisible(FALSE))
  }

  bundle <- remote_download(remote, quiet = quiet)
  on.exit(unlink(bundle), add = TRUE)

  source <- source_pkg(bundle, subdir = remote$subdir)
  on.exit(unlink(source, recursive = TRUE), add = TRUE)

  metadata <- remote_metadata(remote, bundle, source)

  install(source, ..., quiet = quiet, metadata = metadata)
}

install_remotes <- function(remotes, ...) {
  invisible(vapply(remotes, install_remote, ..., FUN.VALUE = logical(1)))
}

# Add metadata
add_metadata <- function(pkg_path, meta) {
  # During installation, the DESCRIPTION file is read and an package.rds file
  # created with most of the information from the DESCRIPTION file. Functions
  # that read package metadata may use either the DESCRIPTION file or the
  # package.rds file, therefore we attempt to modify both of them, and return an
  # error if neither one exists.
  source_desc <- file.path(pkg_path, "DESCRIPTION")
  binary_desc <- file.path(pkg_path, "Meta", "package.rds")
  if (file.exists(source_desc)) {
    desc <- read_dcf(source_desc)

    desc <- modifyList(desc, meta)

    write_dcf(source_desc, desc)
  }

  if (file.exists(binary_desc)) {
    pkg_desc <- base::readRDS(binary_desc)
    desc <- as.list(pkg_desc$DESCRIPTION)
    desc <- modifyList(desc, meta)
    pkg_desc$DESCRIPTION <- stats::setNames(as.character(desc), names(desc))
    base::saveRDS(pkg_desc, binary_desc)
  }

  if (!file.exists(source_desc) && !file.exists(binary_desc)) {
    stop("No DESCRIPTION found!", call. = FALSE)
  }

}

# Modify the MD5 file - remove the line for DESCRIPTION
clear_description_md5 <- function(pkg_path) {
  path <- file.path(pkg_path, "MD5")

  if (file.exists(path)) {
    text <- readLines(path)
    text <- text[!grepl(".*\\*DESCRIPTION$", text)]

    writeLines(text, path)
  }
}

remote <- function(type, ...) {
  structure(list(...), class = c(paste0(type, "_remote"), "remote"))
}
is.remote <- function(x) inherits(x, "remote")

different_sha <- function(remote_sha = NULL,
                          local_sha = NULL) {
  if (is.null(remote_sha)) {
    remote_sha <- remote_sha(remote)
  }

  if (is.null(local_sha)) {
    local_sha <- local_sha(remote_package_name(remote))
  }

  same <- remote_sha == local_sha
  same <- isTRUE(same) && !is.na(same)
  !same
}

local_sha <- function(name) {
  if (!is_installed(name)) {
    return(NA_character_)
  }
  package2remote(name)$sha %||% NA_character_
}

remote_download <- function(x, quiet = FALSE) UseMethod("remote_download")
remote_metadata <- function(x, bundle = NULL, source = NULL) UseMethod("remote_metadata")
remote_package_name <- function(remote, ...) UseMethod("remote_package_name")
remote_sha <- function(remote, ...) UseMethod("remote_sha")

package2remote <- function(x, repos = getOption("repos"), type = getOption("pkgType")) {

  x <- tryCatch(packageDescription(x), error = function(e) NA, warning = function(e) NA)

  # will be NA if not installed
  if (identical(x, NA)) {
    return(NULL)
  }

  if (is.null(x$RemoteType)) {

    # Packages installed with install.packages()
    if (!is.null(x$Repository) && x$Repository == "CRAN") {
      return(remote("cran",
        name = x$Package,
        repos = repos,
        pkg_type = type,
        sha = x$Version))
    } else {
      return(NULL)
    }
  }

  switch(x$RemoteType,
    github = remote("github",
      host = x$RemoteHost,
      repo = x$RemoteRepo,
      subdir = x$RemoteSubdir,
      username = x$RemoteUsername,
      ref = x$RemoteRef,
      sha = x$RemoteSha),
    git = remote("git",
      url = x$RemoteUrl,
      ref = x$RemoteRef,
      sha = x$RemoteSha,
      subdir = x$RemoteSubdir),
    bitbucket = remote("bitbucket",
      host = x$RemoteHost,
      repo = x$RemoteRepo,
      username = x$RemoteUsername,
      ref = x$RemoteRef,
      sha = x$RemoteSha,
      subdir = x$RemoteSubdir),
    svn = remote("svn",
      url = x$RemoteUrl,
      svn_subdir = x$RemoteSvnSubdir,
      branch = x$RemoteBranch,
      sha = x$RemoteRevision,
      args = x$RemoteArgs),
    local = remote("local",
      path = x$RemoteUrl,
      branch = x$RemoteBranch,
      subdir = x$RemoteSubdir,
      sha = x$RemoteSha,
      username = x$RemoteUsername,
      repo = x$RemoteRepo),
    url = remote("url",
      url = x$RemoteUrl,
      subdir = x$RemoteSubdir,
      config = x$RemoteConfig),

    # packages installed with install_cran
    cran = remote("cran",
      name = x$RemoteName,
      repos = eval(parse(text = x$RemoteRepos)),
      pkg_type = x$RemotePkgType,
      sha = x$RemoteSha
      )
    )
}

#' @export
format.remotes <- function(x, ...) {
  vapply(x, format, character(1))
}
