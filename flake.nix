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
      # Published Linux x86-64 Python wheel, GPL-3.0-only. The hash fixes both
      # the engine and its Python interface for the benchmark environment.
      grobx = pkgs.python3Packages.buildPythonPackage {
        pname = "grobx";
        version = "0.73.3";
        format = "wheel";
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/99/23/2a0838556c7497db90daaae7c9ff409598933151797b19d9d3cc4ae6e718/grobx-0.73.3-cp312-abi3-manylinux_2_28_x86_64.whl";
          hash = "sha256-5xAO+gxGgXW9oK73sdo/xYLj89NylwRBPgSK2wfAJRk=";
        };
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        pythonImportsCheck = [ "grobx" ];
        meta.license = pkgs.lib.licenses.gpl3Only;
      };
      python = pkgs.python3.withPackages (p: [ p.sympy p.numpy grobx ]);
      # the CortexJS Compute Engine (MathJSON, JavaScript), pinned by the npm tarball; driven by Node.js
      computeEngine = pkgs.fetchzip {
        url = "https://registry.npmjs.org/@cortex-js/compute-engine/-/compute-engine-0.194.3.tgz";
        hash = "sha256-fHTNsGJbDBnsEGOTxOAU6dXQXZFtPBskExgV+Cb68CI=";
      };
      runtimeInputs = [ julia python pkgs.git pkgs.util-linux pkgs.coreutils pkgs.maxima pkgs.fricas pkgs.sage pkgs.giac pkgs.macaulay2 pkgs.nodejs_24 ];   # Maxima, FriCAS, SageMath (and the giac binary it drives), Macaulay2, Node.js for the Compute Engine
      envHook = ''
        export JULIA_PYTHONCALL_EXE=${python}/bin/python3
        export JULIA_CONDAPKG_BACKEND=Null
        export JULIA_NUM_THREADS=1
        export OPENBLAS_NUM_THREADS=1
        export JULIA_PKG_PRECOMPILE_AUTO=1
        export COMPUTE_ENGINE_DIR=${computeEngine}
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
          h="''${BENCH_HOST:-$(hostname)}"
          mkdir -p "results/$h"
          {
            echo "# environment capture $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            echo "flake_rev ${self.rev or "dirty"}"
            echo "nixpkgs_rev ${nixpkgs.rev}"
            julia --startup-file=no -e 'using InteractiveUtils; versioninfo()'
            lscpu
          } >> "results/$h/environment.txt" 2>&1
          exec nice -n 10 julia --startup-file=no run_all.jl "$@"
        '';
      };
    in {
      packages.${system} = { inherit julia bench grobx; grobx-python = python; default = bench; };
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
