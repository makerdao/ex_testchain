# Nix derivation for Node packages

To update the Nix derivations, edit `node-packages.json` and add any NPM
packages desired.

Then run:

```sh
node2nix -8 -i node-packages.json
```

Install `node2nix` with: `nix-env -iA nodePackages.node2nix`.

[node2nix docs](https://github.com/svanderburg/node2nix#deploying-a-collection-of-npm-packages-from-the-npm-registry)
