{ lib, rustPlatform, fetchFromGitHub }: rustPlatform.buildRustPackage rec {
  pname = "serverctl";
  version = "0.1";

  src = fetchFromGitHub {
    owner = "Lama3L9R";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-acn73AfPSH0YiKcLP/iyPpiyej1cghKx5nubPnzM/dI=";
  };

  cargoHash = "sha256-UVS4y6IDsjcPjkwxLIB0QuQokABIMqrwnETqiu+EALY=";

  buildInputs = [ ];

  meta = with lib; {
    description = "CHANGE";
    homepage = "https://github.com/Lama3L9R/serverctl";
    license = "Anti-996";
    maintainers = with maintainers; [  ];
  };
}
