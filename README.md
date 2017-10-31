DISCLAIMER: This project is no longer maintained. Instead use [node2nix](https://github.com/svanderburg/node2nix)
-----------

npm2nix
=======

Generate nix expressions from npmjs.org!


Usage
-----

`npm2nix [--no-dev] node-packages.json node-packages.generated.nix`

`no-dev` ignores development dependencies

JSON structure
--------------

npm2nix expects the passed JSON file to be a list of strings and at most one
object. Strings are taken as the name of the package. The object must be
a valid dependencies object for an for an npm `packages.json` file.
Alternatively, the passed JSON file can be an npm `package.json`, in which
case the expressions for its dependencies will be generated.

Development
-----------

- `nix-shell`
- `grunt watch`

Release
-------

- `export GITHUB_USERNAME=<your_github_username>`
- `export GITHUB_PASSWORD=<your_github_password>`
- `grunt release:patch/minor/major`
