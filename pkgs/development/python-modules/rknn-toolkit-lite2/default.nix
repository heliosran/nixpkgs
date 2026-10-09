{
  autoPatchelfHook,
  buildPythonPackage,
  fetchurl,
  lib,
  librknnrt,
  numpy,
  psutil,
  python,
  ruamel-yaml,
  stdenv,
}:

let
  version = "2.3.2";
in
buildPythonPackage {
  pname = "rknn-toolkit-lite2";
  inherit version;
  format = "wheel";
  disabled = lib.versions.majorMinor python.version != "3.12";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/ff/db/64c756f3f06b219e92ff4f0fd4e000870ee49f214d505ff01c8b0275e26d/rknn_toolkit_lite2-${version}-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl";
    hash = "sha256-4eTsaR/tkAwOb95efY7roX+AaqRQkrY7Nh7ndeLBtQ4=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  # The binding loads this library by its absolute /usr/lib path. The NixOS
  # machine-learning service exposes the separately packaged runtime there in
  # its mount namespace.
  buildInputs = [
    librknnrt
    stdenv.cc.cc.lib
  ];

  dependencies = [
    numpy
    psutil
    ruamel-yaml
  ];

  postInstall = ''
    install -Dm644 ${librknnrt.sdkLicense} "$out/share/licenses/rknn-toolkit-lite2/LICENSE"
  '';

  # The top-level package is empty; importing the API loads the compiled
  # extensions without initializing an NPU or downloading a model.
  pythonImportsCheck = [ "rknnlite.api" ];

  meta = {
    description = "Python Lite API for Rockchip NPU inference";
    homepage = "https://github.com/airockchip/rknn-toolkit2/tree/master/rknn-toolkit-lite2";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
