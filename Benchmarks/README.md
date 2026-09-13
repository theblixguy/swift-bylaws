# Local benchmarks

The benchmark package measures parsing, queries and CLI runs. To run the parser
and query benchmarks, use this command from the repository root:

```sh
swift package --package-path Benchmarks benchmark
```

If you want to include CLI benchmarks, build the release executable and pass its
path:

```sh
swift build -c release --product bylaws
BYLAWS_BENCHMARK_CLI="$PWD/.build/release/bylaws" swift package --package-path Benchmarks benchmark
```

## Read the results

Each CLI measurement starts a new process with the disk cache disabled and
includes startup, rule loading and file collection as well as the checks
themselves. The CLI results include only timings because the memory and
allocation counters measure the parent benchmark process.

The parser and query benchmarks run inside the benchmark process, where those
counters apply. To compare builds, run the same benchmark case on the same
machine with the same settings.
