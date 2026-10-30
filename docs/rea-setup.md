# REA setup on this Mac

On 2026-10-30, REA 6.8.0's `rea doctor` reported Node 22.18.0 too old, no analysis providers, a missing skill, and missing client registrations. Node 24.21.0 is also too old. Java 17 is installed. Homebrew's current Ghidra formula is 12.2, while this REA doctor asks for Ghidra 12.1.x, so use the pinned release instead of the formula:

```sh
source "$HOME/.nvm/nvm.sh"
nvm install 22.23.4
nvm use 22.23.4
npm install -g rea-agents@6.8.0
brew install openjdk@21
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
mkdir -p "$HOME/Applications/ghidra"
gh release download Ghidra_12.1.4_build --repo NationalSecurityAgency/ghidra --pattern 'ghidra_12.1.4_PUBLIC_20260921.zip' --dir "$HOME/Applications/ghidra"
unzip "$HOME/Applications/ghidra/ghidra_12.1.4_PUBLIC_20260921.zip" -d "$HOME/Applications/ghidra"
export GHIDRA_INSTALL_DIR="$HOME/Applications/ghidra/ghidra_12.1.4_PUBLIC"
rea doctor --provider ghidra
```

These user-local nvm, Homebrew formula, and download commands normally require no sudo with a working user-owned Homebrew installation. Persist the exports in the shell configuration if needed. The scoped doctor is the appropriate verification for Ghidra; an unscoped audit also reports missing Hopper, IDA, JADX, Kuna, the REA skill, and registrations for multiple clients. `rea setup` can configure the chosen client and skill; making the full audit healthy additionally requires configuring all providers and client registrations. None of these installations or configuration changes was performed here. See the [Ghidra release](https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.1.4_build).
