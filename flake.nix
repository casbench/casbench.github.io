{
  # Reproducible toolchain for the paper benchmarks.
  #
  #   nix develop ./benchmark            # shell with julia, python3+sympy, git
  #   nix run ./benchmark#bench          # run every bench (benchmark/run_all.jl)
  #   nix develop ./benchmark#paper      # shell with latexmk, texlive and ruby for paper/
  #
  # nixpkgs is pinned by flake.lock. Julia is the official 1.13.3 binary
  # tarball (nixpkgs only ships 1.12 at the pinned revision), patched for the
  # Nix store the same way nixpkgs' julia-bin is. Python is the nixpkgs
  # interpreter with sympy; PythonCall is pointed at it so that CondaPkg does
  # not resolve anything at run time. Giac, PARI and the C++ wrapper come from
  # the Julia artifacts pinned in the environments' Manifest.toml files.
  description = "Giac.jl JuliaCon proceedings benchmarks";

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
      python = pkgs.python3.withPackages (p: [ p.sympy ]);
      runtimeInputs = [ julia python pkgs.git pkgs.util-linux pkgs.coreutils ];
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
        paper = pkgs.mkShell {
          packages = [
            (pkgs.texliveMedium.withPackages (ps: with ps; [ preprint eurosym psnfss microtype caption listings xcolor hyperref url latexmk ]))
            pkgs.ruby pkgs.ghostscript
          ];
        };
      };
    };
}
