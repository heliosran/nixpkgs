# These evaluation checks do not require a Rockchip board or build the SDK.
# Run with: nix-build -A nixosTests.immich-rknn-eval
{
  pkgs,
  lib ? pkgs.lib,
}:
let
  eval = import ../../lib/eval-config.nix;
  mkConfig =
    system: extra:
    eval {
      inherit system;
      modules = [
        {
          services.immich.enable = true;
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "ext4";
          };
          system.stateVersion = "25.11";
          nixpkgs.config.allowUnfree = system == "aarch64-linux";
        }
        extra
      ];
    };
  rknnConfig = {
    services.immich = {
      machine-learning.acceleration = "rknn";
      accelerationDevices = [ "/dev/dri/renderD128" ];
    };
  };
  cpu = mkConfig "x86_64-linux" { };
  rknn = mkConfig "aarch64-linux" rknnConfig;
  allDevices = rknn.extendModules {
    modules = [ { services.immich.accelerationDevices = lib.mkForce null; } ];
  };
  noDevices = rknn.extendModules {
    modules = [ { services.immich.accelerationDevices = lib.mkForce [ ]; } ];
  };
  wrongArch = mkConfig "x86_64-linux" rknnConfig;
  disabled = mkConfig "x86_64-linux" {
    services.immich.machine-learning = {
      enable = false;
      acceleration = "rknn";
    };
  };
  customized = rknn.extendModules {
    modules = [
      {
        services.immich = {
          user = "custom-immich";
          machine-learning.environment = {
            MACHINE_LEARNING_RKNN = "False";
            MACHINE_LEARNING_RKNN_THREADS = "3";
          };
        };
        users.users.custom-immich = {
          isSystemUser = true;
          group = "immich";
        };
        users.groups.npu = { };
        systemd.services.immich-machine-learning.serviceConfig.SupplementaryGroups = [ "npu" ];
      }
    ];
  };
  service = configuration: configuration.config.systemd.services.immich-machine-learning;
  accelerationEnvironment =
    configuration:
    lib.filterAttrs (name: _: lib.hasPrefix "MACHINE_LEARNING_RKNN" name)
      (service configuration).environment;
  assertionMessages =
    configuration:
    map (assertion: assertion.message) (
      lib.filter (assertion: !assertion.assertion) configuration.config.assertions
    );
  failures = lib.runTests {
    testAvailableBackends = {
      expr = map cpu.options.services.immich.machine-learning.acceleration.type.check [
        null
        "rknn"
        "cuda"
        "rocm"
      ];
      expected = [
        true
        true
        false
        false
      ];
    };
    testCpuDefaults = {
      expr = {
        assertions = assertionMessages cpu;
        environment = accelerationEnvironment cpu;
        privateDevices = (service cpu).serviceConfig.PrivateDevices;
        privateUsers = (service cpu).serviceConfig.PrivateUsers;
        binds = (service cpu).serviceConfig.BindReadOnlyPaths;
        groups = (service cpu).serviceConfig.SupplementaryGroups;
        command = (service cpu).serviceConfig.ExecStart;
      };
      expected = {
        assertions = [ ];
        environment = { };
        privateDevices = true;
        privateUsers = true;
        binds = [ ];
        groups = [ ];
        command = lib.getExe cpu.pkgs.immich.machine-learning;
      };
    };
    testRknnSandbox = {
      expr = {
        assertions = assertionMessages rknn;
        environment = accelerationEnvironment rknn;
        privateDevices = (service rknn).serviceConfig.PrivateDevices;
        privateUsers = (service rknn).serviceConfig.PrivateUsers;
        protectKernelTunables = (service rknn).serviceConfig.ProtectKernelTunables;
        deviceAllow = (service rknn).serviceConfig.DeviceAllow;
        groups = (service rknn).serviceConfig.SupplementaryGroups;
        binds = (service rknn).serviceConfig.BindReadOnlyPaths;
        command = (service rknn).serviceConfig.ExecStart;
      };
      expected = {
        assertions = [ ];
        environment.MACHINE_LEARNING_RKNN = "True";
        privateDevices = false;
        privateUsers = true;
        protectKernelTunables = true;
        deviceAllow = [ "/dev/dri/renderD128" ];
        groups = [
          "video"
          "render"
        ];
        binds = [
          "${rknn.pkgs.librknnrt}/lib/librknnrt.so:/usr/lib/librknnrt.so"
          "-/sys/firmware/devicetree/base"
        ];
        command = lib.getExe (rknn.pkgs.immich.machine-learning.override { rknnSupport = true; });
      };
    };
    testAllDevices = {
      expr = {
        assertions = assertionMessages allDevices;
        privateDevices = (service allDevices).serviceConfig.PrivateDevices;
      };
      expected = {
        assertions = [ ];
        privateDevices = false;
      };
    };
    testBlockedNpu = {
      expr = assertionMessages noDevices;
      expected = [
        "`services.immich.accelerationDevices` must allow the NPU device when `services.immich.machine-learning.acceleration` is `\"rknn\"`."
      ];
    };
    testUnsupportedPlatform = {
      expr = {
        assertions = assertionMessages wrongArch;
        # Forcing ExecStart must not mask the module assertion with a package
        # evaluation error on unsupported architectures.
        command = (service wrongArch).serviceConfig.ExecStart;
      };
      expected = {
        assertions = [
          "`services.immich.machine-learning.acceleration = \"rknn\"` requires aarch64-linux."
        ];
        command = lib.getExe wrongArch.pkgs.immich.machine-learning;
      };
    };
    testDisabledMachineLearning = {
      expr = {
        assertions = assertionMessages disabled;
        hasService = disabled.config.systemd.services ? immich-machine-learning;
      };
      expected = {
        assertions = [ ];
        hasService = false;
      };
    };
    testCustomUserAndEnvironment = {
      expr = {
        assertions = assertionMessages customized;
        user = (service customized).serviceConfig.User;
        groups = lib.sort builtins.lessThan (service customized).serviceConfig.SupplementaryGroups;
        environment = accelerationEnvironment customized;
      };
      expected = {
        assertions = [ ];
        user = "custom-immich";
        groups = [
          "npu"
          "render"
          "video"
        ];
        environment = {
          MACHINE_LEARNING_RKNN = "False";
          MACHINE_LEARNING_RKNN_THREADS = "3";
        };
      };
    };
  };
in
assert lib.assertMsg (failures == [ ]) (builtins.toJSON failures);
pkgs.emptyFile
