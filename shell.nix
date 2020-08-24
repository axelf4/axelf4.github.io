{ pkgs ? import <nixpkgs> {} }: with pkgs; pkgs.mkShell {
	buildInputs = [
		ruby
		libxml2
	];
}
