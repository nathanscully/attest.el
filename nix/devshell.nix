{ pkgs, emacs, treefmtWrapper }:

{
  default = {
    packages = [ emacs.emacs pkgs.pnpm ] ++ emacs.runners;

    devshell = {
      motd = ''

          A T T E S T

          → check        compile + checkdoc + ert (the full gate)
          → ert          the ert suite only
          → stress       live runs against stress/
          → package      stage the installable tar
          → fmt          format everything
          → menu         full command list
      '';
      startup.direnv.text = pkgs.lib.mkForce "";
    };

    env = [
      {
        name = "EMACS_TREE_SITTER_GRAMMARS";
        value = "${emacs.grammars}/lib";
      }
    ];

    commands = [
      {
        category = "check";
        name = "check";
        help = "Byte-compile (warnings are errors), checkdoc and ert";
        command = ''
          set -e
          compile
          checkdoc
          ert
        '';
      }
      {
        category = "check";
        name = "compile";
        help = "Byte-compile every source file, warnings as errors";
        command = emacs.scripts.compile;
      }
      {
        category = "check";
        name = "checkdoc";
        help = "Run checkdoc over every source file";
        command = emacs.scripts.checkdoc;
      }
      {
        category = "check";
        name = "ert";
        help = "Run the ert suite (excludes stress)";
        command = emacs.scripts.test;
      }
      {
        category = "check";
        name = "stress";
        help = "Spawn every runner against the projects under stress/";
        command = emacs.scripts.stress;
      }
      {
        category = "package";
        name = "package";
        help = "Stage the installable tar with generated autoloads";
        command = emacs.scripts.package;
      }
      {
        category = "package";
        name = "package-test";
        help = "Install the staged tar into a clean Emacs and load it";
        command = emacs.scripts.package-test;
      }
      {
        category = "package";
        name = "clean";
        help = "Remove the staged package";
        command = emacs.scripts.clean;
      }
      {
        category = "dev";
        name = "fmt";
        help = "Format every source file treefmt owns";
        command = "${treefmtWrapper}/bin/treefmt \"$@\"";
      }
    ];
  };
}
