# Install fixtures

`test-install.sh` creates its target repositories dynamically because an install
fixture is a whole directory, not one Claude Code stdin event. It covers a clean
install and a reinstall over user-modified settings. The profile-specific
no-React-hook case becomes executable with chantier 7, where profiles are added.
