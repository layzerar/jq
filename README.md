# jq

`jq` is a lightweight and flexible command-line JSON processor akin to `sed`,`awk`,`grep`, and friends for JSON data. It's written in portable C and has zero runtime dependencies, allowing you to easily slice, filter, map, and transform structured data.

## Documentation

- **Official Documentation**: [jqlang.org](https://jqlang.org)
- **Try jq Online**: [play.jqlang.org](https://play.jqlang.org)

## Installation

### Prebuilt Binaries

Download the latest releases from the [GitHub release page](https://github.com/jqlang/jq/releases).

### Docker Image

Pull the [jq image](https://github.com/jqlang/jq/pkgs/container/jq) to start quickly with Docker.

#### Run with Docker

##### Example: Extracting the version from a `package.json` file

```bash
docker run --rm -i ghcr.io/jqlang/jq:latest < package.json '.version'
```

##### Example: Extracting the version from a `package.json` file with a mounted volume

```bash
docker run --rm -i -v "$PWD:$PWD" -w "$PWD" ghcr.io/jqlang/jq:latest '.version' package.json
```

### Building from source

#### Dependencies

- libtool
- make
- automake
- autoconf

#### Instructions

```console
git submodule update --init    # if building from git to get oniguruma
autoreconf -i                  # if building from git
./configure --with-oniguruma=builtin
make clean                     # if upgrading from a version previously built from source
make -j8
make check
sudo make install
```

Build a statically linked version:

```console
make LDFLAGS=-all-static
```

If you're not using the latest git version but instead building a released tarball (available on the release page), skip the `autoreconf` step, and flex or bison won't be needed.

#### Building with CMake

A CMake build is also provided as an alternative to autoconf/automake. It
mirrors the same feature checks and produces the same `jq` executable,
`libjq` (shared and static) and `libjq.pc` outputs.

```console
git submodule update --init    # if building from git to get oniguruma
cmake -S . -B build -DJQ_BUILD_ONIGURUMA=builtin
cmake --build build -j
ctest --test-dir build --output-on-failure
sudo cmake --install build
```

Useful options (pass with `-D<name>=<value>`):

- `JQ_BUILD_ONIGURUMA` — `auto` (default), `system`, `builtin`, or `off`
- `JQ_ENABLE_DECNUM` — enable decNumber support (default `ON`)
- `JQ_ENABLE_ALL_STATIC` — link `jq` fully statically (default `OFF`)
- `JQ_ENABLE_ASAN` / `JQ_ENABLE_UBSAN` / `JQ_ENABLE_GCOV` — sanitizers and coverage
- `JQ_BUILD_SHARED_LIB` / `JQ_BUILD_STATIC_LIB` — choose which `libjq` flavors to build
- `JQ_BUILD_TESTS` — register the test suite with CTest (default `ON`)

##### Cross-Compilation

For details on cross-compilation, check out the [GitHub Actions file](.github/workflows/ci.yml) and the [cross-compilation wiki page](https://github.com/jqlang/jq/wiki/Cross-compilation).

## Community & Support

- Questions & Help: [Stack Overflow (jq tag)](https://stackoverflow.com/questions/tagged/jq)
- Chat & Community: [Join us on Discord](https://discord.gg/yg6yjNmgAC)
- Wiki & Advanced Topics: [Explore the Wiki](https://github.com/jqlang/jq/wiki)

## License

`jq` is released under the [MIT License](COPYING). `jq`'s documentation is
licensed under the [Creative Commons CC BY 3.0](COPYING).
`jq` uses parts of the open source C library "decNumber", which is distributed
under [ICU License](COPYING)
