# Simple Certificate Authority

Simple file based Certificate Authority with OpenSSL.

---

This is a simple certificate authority based and build around the materials offered by e.g.
[Jamie Linux](https://jamielinux.com/docs/openssl-certificate-authority/index.html).

Before using this also have a look at e.g. [CFSSL](https://github.com/cloudflare/cfssl). The scripts contained in this
repository are a showcase/local development setup implementation of an TLS Certificate Authority setup only.

The shell script template used for the generator scripts is the MIT licensed
[script-template.sh](https://gist.github.com/m-radzikowski/53e0b39e9a59a1518990e76c2bff8038) by Maciej Radzikowski.

## Required Software

- [bash](https://www.gnu.org/software/bash/) scripting environment
- [OpenSSL](https://www.openssl.org) SSL implementation: **This script requires OpenSSL and not one of the other
  implementations such as LibreSSL.**
- [ssh](https://www.openssh.com) SSH implementation

### macOS

Install OpenSSL via e.g. [Homebrew](https://formulae.brew.sh/formula/openssl@3) – macOS ships with LibreSSL which is not
supported. The path at which the OpenSSL binary is located can be found with:

```bash
$ brew info openssl@3
# Documentation and Caveats...
If you need to have openssl@3 first in your PATH, run:
  echo 'export PATH="/usr/local/opt/openssl@3/bin:$PATH"' >> /Users/ng/.bash_profile
# ...
# This means that openssl should be available at /usr/local/opt/openssl@3/bin/openssl
$ /usr/local/opt/openssl@3/bin/openssl version
OpenSSL 3.0.0 7 sep 2021 (Library: OpenSSL 3.0.0 7 sep 2021)
```

You can now invoke the scripts with the `-l /usr/local/opt/openssl@3/bin/openssl` parameter.

**Hint:** the older [OpenSSL 1.1](https://formulae.brew.sh/formula/openssl@1.1) can also be used and works exactly the
same.

Additionally, a GNU compatible `date` binary is required, for example available via:

```bash
$ brew info coreutils
# Documentation and Caveats...
If you need to use these commands with their normal names, you can add a "gnubin" directory to your PATH with:
  PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
# ...
# This means that date should be available at /usr/local/opt/coreutils/libexec/gnubin/date
$ /usr/local/opt/coreutils/libexec/gnubin/date --version
date (GNU coreutils) 9.0
```

If you don't want to put this permanently onto your path you can simply prefix any `./scripts/*.sh` invocations with
`PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"`, i.e.:

```bash
$ PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH" ./scripts/host-certificate.sh
```

### Windows

- For a Bash based environment it is easiest to use [Git for Windows](https://gitforwindows.org)
  - make sure to select the Windows Terminal Profile Fragment during installation for a better user experience later
    on
  - also make sure to use the Windows Secure Channel library if you plan on rolling out certificates to your machine
    otherwise you'll have to manually patch the bundled certificate bundle
  - make sure to use "Checkout as-is, commit as-is" to not break line endings of existing files
  - this includes a compatible OpenSSH and a compatible OpenSSL version by default
- Instead of using the MinTTY console installed by Git consider
  use [Windows Terminal](https://github.com/microsoft/terminal) instead for a better user experience
- For a simple installation consider using [Scoop](https://scoop.sh)

## Run in local Bash

Check the help for details on how to use this script and what options are available.

```bash
./scripts/host-generator.sh --help
./scripts/intermediate-generator.sh --help
./scripts/ssh-generator.sh --help
./scripts/host-certificate.sh --help
```

### First usage

**HINT:** Instead of using the parameters `-p` and `-w` to provide passwords inline you can also use the following
environment variables: `SIMPLE_CA_ROOT_PASSWORD`, `SIMPLE_CA_INTERMEDIATE_PASSWORD`, `SIMPLE_CA_SSH_PASSWORD`

A secondary `root_env.cnf` exists that can also be used if instead of putting fixed values into a OpenSSH config file
you want to supply configuration values as environment variables.

1. Adapt the configuration files in the `config` folder to your needs by changing the values in
   the `[ req_distinguished_name ]` section and the values in the `[ name_constraints ]` section of the root config.
2. Generate a root certificate authority:
   ```bash
   ./scripts/root-generator.sh -p 'rootpassword' -c ./config/root.cnf -d ./data -n 'root-ca-name'
   ```
3. Generate an intermediate certificate authority:
   ```bash
   ./scripts/intermediate-generator.sh -r ./data/root-ca-name \
   -w 'rootpassword' -g ./config/root.cnf \
   -p 'intermediatepassword' -c ./config/intermediate.cnf \
   -d ./data \
   -n 'intermediate-ca-name'
   ```
4. Generate an SSH certificate authority:
   ```bash
   ./scripts/ssh-generator.sh -d ./data -n 'ssh-ca' -p 'sshpassword'
   ```

### Generating new Host Certificates

Once the initial setup is complete you can start generating host/client certificates to be used based around the root
and intermediate certificate authorities:

```bash
./scripts/host-certificate.sh -c ./config/intermediate.cnf -d ./data/intermediate-ca-name \
 -p 'intermediatepassword' \
 -n 'host cname' \
 -t 'altname,altname.local' \
 --client --server
```

Don't forget to read the documentation via `--help` to see what other flags and settings can be specified.
