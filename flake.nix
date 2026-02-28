{
  description = "Clickhouse client";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        erlang = pkgs.beam.packages.erlang_27.erlang;
      in
      {
        formatter = pkgs.nixfmt-rfc-style;
        devShell =
          with pkgs;
          mkShell {
            buildInputs = [
              erlang
              erlfmt
              go
              lz4
              rebar3
            ];

            shellHook = ''
              echo "Erlang $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell) is ready"
              export GOPATH=$(pwd)/.gopath
              mkdir -p $GOPATH
            '';
          };
      }
    );
}
