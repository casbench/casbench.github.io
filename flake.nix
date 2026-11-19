{
  # Reproducible toolchain for the benchmarks.
  #
  #   nix develop               # shell with julia, python3+sympy, git
  #   nix run .#bench           # run every bench (run_all.jl)
  #   nix develop .#site        # shell with hugo, go and python3 for tools/site/build.sh
  #
  # When this repository is the `benchmark` submodule of the paper repository,
  # the same commands work with ./benchmark in place of `.`.
  #
  # nixpkgs is pinned by flake.lock. Julia is the official 1.13.3 binary
  # tarball (nixpkgs only ships 1.12 at the pinned revision), patched for the
  # Nix store the same way nixpkgs' julia-bin is. Python is the nixpkgs
  # interpreter with sympy; PythonCall is pointed at it so that CondaPkg does
  # not resolve anything at run time. Giac, PARI and the C++ wrapper come from
  # the Julia artifacts pinned in the environments' Manifest.toml files.
  description = "Computer algebra system benchmarks (Giac.jl, Symbolics.jl, SymPy, SymJ.jl, Primes.jl, LibPARI.jl)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      juliaVersion = "1.13.3";
      julia = pkgs.stdenv.mkDerivation {
        pname = "julia-bin";
        version = juliaVersion;
        src = pkgs.fetchurl {
          url = "https://julialang-s3.julialang.org/bin/linux/x64/1.13/julia-${juliaVersion}-linux-x86_64.tar.gz";
          sha256 = "1r33bkw1657h37nns4d1lk597h6sypi7jxsfa2ivab1k815wnqaw";
        };
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib ];
        autoPatchelfIgnoreMissingDeps = true;
        dontStrip = true;
        installPhase = ''
          mkdir -p $out
          cp -r . $out
        '';
      };
      python = pkgs.python3.withPackages (p: [ p.sympy p.numpy ]);
      runtimeInputs = [ julia python pkgs.git pkgs.util-linux pkgs.coreutils pkgs.maxima pkgs.fricas ];   # Maxima and FriCAS: subprocess adapters of bench F
      envHook = ''
        export JULIA_PYTHONCALL_EXE=${python}/bin/python3
        export JULIA_CONDAPKG_BACKEND=Null
        export JULIA_NUM_THREADS=1
        export OPENBLAS_NUM_THREADS=1
        export JULIA_PKG_PRECOMPILE_AUTO=1
      '';
      bench = pkgs.writeShellApplication {
        name = "bench";
        inherit runtimeInputs;
        text = ''
          ${envHook}
          d="''${BENCH_DIR:-$PWD}"
          [ -f "$d/run_all.jl" ] || d="$PWD/benchmark"
          [ -f "$d/run_all.jl" ] || { echo "run from the repository or benchmark directory, or set BENCH_DIR" >&2; exit 1; }
          cd "$d"
          mkdir -p results
          {
            echo "# environment capture $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            echo "flake_rev ${self.rev or "dirty"}"
            echo "nixpkgs_rev ${nixpkgs.rev}"
            julia --startup-file=no -e 'using InteractiveUtils; versioninfo(verbose=true)'
            lscpu
          } > results/environment.txt 2>&1
          exec nice -n 10 julia --startup-file=no run_all.jl "$@"
        '';
      };
    in {
      packages.${system} = { inherit julia bench; default = bench; };
      apps.${system}.bench = { type = "app"; program = "${bench}/bin/bench"; };
      devShells.${system} = {
        default = pkgs.mkShell {
          packages = runtimeInputs;
          shellHook = envHook;
        };
        site = pkgs.mkShell {
          packages = [ pkgs.hugo pkgs.go pkgs.python3 ];
        };
      };
    };
}
