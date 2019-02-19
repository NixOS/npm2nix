fs = require 'fs'
path = require 'path'

argparse = require 'argparse'
npmconf = require 'npmconf'
RegistryClient = require 'npm-registry-client'

PackageFetcher = require './package-fetcher'

version = require('../package.json').version

parser = new argparse.ArgumentParser {
  version: version
  description: 'Generate nix expressions to build npm packages'
  epilog: """
      The package list can be either an npm package.json, in which case npm2nix
      will generate expressions for its dependencies, or a list of strings and
      at most one object, where the strings are package names and the object is
      a valid dependencies object (see npm.json(5) for details)
    """
}

parser.addArgument [ 'packageList' ],
  help: 'The file containing the packages to generate expressions for'
  type: path.resolve
  metavar: 'INPUT'

parser.addArgument [ 'output' ],
  help: 'The output file to generate'
  type: path.resolve
  metavar: 'OUTPUT'

parser.addArgument [ '--overwrite' ],
  help: 'Whether to overwrite the helper default.nix expression (when generating for a package.json)',
  action: 'storeTrue',

parser.addArgument [ '--nodev' ],
  help: 'Do not generate development dependencies',
  action: 'storeTrue'

args = parser.parseArgs()

escapeNixString = (string) ->
  string.replace /(\\|\$\{|")/g, "\\$&"

fullNames = {}
packageSet = {}

writePkg = finalizePkgs = undefined
do ->

  known = {}

  stream = fs.createWriteStream args.output
  stream.write "{ self, fetchurl, fetchgit ? null, lib }:\n\n{"
  writePkg = (name, spec, pkg) ->
    stream.write """
    \n  by-spec.\"#{escapeNixString name}\".\"#{escapeNixString spec}\" =
        self.by-version.\"#{escapeNixString name}\".\"#{escapeNixString  pkg.version}\";
    """
    unless name of known and pkg.version of known[name]
      known[name] ?= {}
      known[name][pkg.version] = true
      cycleDeps = {}
      cycleDeps[pkg.name] = true

      stream.write "\n  by-version.\"#{escapeNixString pkg.name}\".\"#{escapeNixString pkg.version}\" = self.buildNodePackage {"
      stream.write "\n    name = \"#{escapeNixString pkg.name}-#{escapeNixString pkg.version}\";"
      stream.write "\n    version = \"#{escapeNixString pkg.version}\";"
      stream.write "\n    bin = #{if "bin" of pkg then "true" else "false"};"

      stream.write "\n    src = "

      if 'tarball' of pkg.dist
        stream.write """
        fetchurl {
              url = "#{pkg.dist.tarball}";
              name = "#{pkg.name}-#{pkg.version}.tgz";
              #{if 'shasum' of pkg.dist then 'sha1' else 'sha256'} = "#{pkg.dist.shasum ? pkg.dist.sha256sum}";
            }
        """
      else
        stream.write """
        fetchgit {
              url = "#{pkg.dist.git}";
              rev = "#{pkg.dist.rev}";
              sha256 = "#{pkg.dist.sha256sum}";
            }
        """

      seenDeps = {}

      stream.write ";\n    deps = {"
      for nm, spc of pkg.dependencies or {}
        unless seenDeps[nm] or nm of (pkg.optionalDependencies or {})
          spc = spc.version if spc instanceof Object
          if spc is 'latest' or spc is ''
            spc = '*'
          stream.write "\n      \"#{escapeNixString nm}-#{packageSet[nm][spc].version}\" = self.by-version.\"#{escapeNixString nm}\".\"#{packageSet[nm][spc].version}\";"
          seenDeps[nm] = true

      stream.write "\n    };\n    optionalDependencies = {"
      for nm, spc of pkg.optionalDependencies or {}
        unless seenDeps[nm]
          spc = spc.version if spc instanceof Object
          if spc is 'latest' or spc is ''
            spc = '*'
          stream.write "\n      \"#{escapeNixString nm}-#{packageSet[nm][spc].version}\" = self.by-version.\"#{escapeNixString nm}\".\"#{packageSet[nm][spc].version}\";"
        seenDeps[nm] = true

      stream.write "\n    };\n    peerDependencies = ["
      for nm, spc of pkg.peerDependencies or {}
        unless seenDeps[nm] or cycleDeps[nm]
          spc = spc.version if spc instanceof Object
          if spc is 'latest' or spc is ''
            spc = '*'
          stream.write "\n      self.by-version.\"#{escapeNixString nm}\".\"#{packageSet[nm][spc].version}\""
        seenDeps[nm] = true
      stream.write "];\n"

      stream.write "    os = ["
      for os, i in pkg.os or []
        stream.write " \"#{os}\""
      stream.write " ];\n"

      stream.write "    cpu = ["
      for cpu, i in pkg.cpu or []
        stream.write " \"#{cpu}\""
      stream.write " ];\n"

      stream.write "  };"

    if fullNames[name] is spec
      stream.write """
      \n  "#{escapeNixString name}" = self.by-version."#{escapeNixString pkg.name}"."#{pkg.version}";
      """

  finalizePkgs = ->
    stream.end "\n}\n"

npmconf.load (err, conf) ->
  if err?
    console.error "Error loading npm config: #{err}"
    process.exit 7
  registry = new RegistryClient conf
  fetcher = new PackageFetcher()
  fs.readFile args.packageList, (err, json) ->
    if err?
      console.error "Error reading file #{args.packageList}: #{err}"
      process.exit 1
    try
      packages = JSON.parse json
    catch error
      console.error "Error parsing JSON file #{args.packageList}: #{error}"
      process.exit 3

    packageByVersion = {}

    pendingPackages = []

    checkPendingPackages = () ->
      console.log "Waiting for #{pendingPackages} to complete ..."
    checkInterval = setInterval checkPendingPackages, 10000

    fetcher.on 'fetching', (name, spec) ->
      pendingPackages.push(name)
    fetcher.on 'fetched', (name, spec, pkg) ->
      pendingPackageIndex = pendingPackages.indexOf(name)
      console.assert (pendingPackageIndex >= 0), "Package #{name} was fetched multiple times!"
      pendingPackages.splice(pendingPackageIndex,1)
      packageByVersion[name] ?= {}
      unless pkg.version of packageByVersion[name]
        packageByVersion[name][pkg.version] = pkg
      packageSet[name] ?= {}
      packageSet[name][spec] = packageByVersion[name][pkg.version]
      if pendingPackages.length == 0
        clearInterval(checkInterval)
        names = (key for key, val of packageSet).sort()
        for name in names
          specs = (key for key, val of packageSet[name]).sort()
          for spec in specs
            writePkg name, spec, packageSet[name][spec]
        finalizePkgs()

    fetcher.on 'error', (err, name, spec) ->
      console.error "Error during fetch: #{err}"
      process.exit 8

    addPackage = (name, spec) ->
      spec = '*' if spec is 'latest' or spec is '' #ugh
      fullNames[name] = spec
      fetcher.fetch name, spec, registry
    if packages instanceof Array
      for pkg in packages
        if typeof pkg is "string"
          addPackage pkg, '*'
        else
          addPackage name, spec for name, spec of pkg
    else if packages instanceof Object
      unless 'dependencies' of packages or 'devDependencies' of packages
        console.error "#{file} specifies no dependencies"
        process.exit 6

      addPackage name, spec for name, spec of packages.dependencies ? {}
      addPackage name, spec for name, spec of packages.devDependencies ? {} if !args.nodev

      pkgName = escapeNixString packages.name
      fs.writeFile "default.nix", """
        { #{pkgName} ? { outPath = ./.; name = "#{pkgName}"; }
        , pkgs ? import <nixpkgs> {}
        }:
        let
          nodePackages = import "${pkgs.path}/pkgs/top-level/node-packages.nix" {
            inherit pkgs;
            inherit (pkgs) stdenv nodejs fetchurl fetchgit;
            neededNatives = [ pkgs.python ] ++ pkgs.lib.optional pkgs.stdenv.isLinux pkgs.utillinux;
            self = nodePackages;
            generated = ./#{path.relative process.cwd(), args.output};
          };
        in rec {
          tarball = pkgs.runCommand "#{pkgName}-#{packages.version}.tgz" { buildInputs = [ pkgs.nodejs ]; } ''
            mv `HOME=$PWD npm pack ${#{pkgName}}` $out
          '';
          build = nodePackages.buildNodePackage {
            name = "#{pkgName}-#{packages.version}";
            src = [ tarball ];
            buildInputs = nodePackages.nativeDeps."#{pkgName}" or [];
            deps = [ #{
              ("nodePackages.by-spec.\"#{escapeNixString nm}\".\"#{escapeNixString spc}\"" for nm, spc of (packages.dependencies ? {})).join ' '
            } ];
            peerDependencies = [];
          }""" + (!args.nodev and """;
          dev = build.override {
            buildInputs = build.buildInputs ++ [ #{
              ("nodePackages.by-spec.\"#{escapeNixString nm}\".\"#{escapeNixString spc}\"" for nm, spc of (packages.devDependencies ? {})).join ' '
            } ];
          };
        }
        """ or """;
        }
        """), flag: "w#{if args.overwrite then '' else 'x'}", (err) ->
          if err? and err.code isnt 'EEXIST'
            console.error "Error writing helper default.nix: #{err}"
    else
      console.error "#{file} must represent an array of packages or be a valid npm package.json"
      process.exit 4
