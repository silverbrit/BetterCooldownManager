#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
libraries_dir="${script_dir}/Libraries"
local_libraries_dir="${script_dir}/.libraries"
staging_dir=""

cleanup() {
  if [[ -n "${staging_dir}" && -d "${staging_dir}" ]]; then
    rm -rf "${staging_dir}"
  fi
}

trap cleanup EXIT

if [[ ! -f "${script_dir}/BetterCooldownManager.toc" ]]; then
  echo "Error: BetterCooldownManager.toc not found in ${script_dir}." >&2
  echo "Run this script from the BetterCooldownManager repo root." >&2
  exit 1
fi

if [[ ! -f "${libraries_dir}/Init.xml" ]]; then
  echo "Error: Libraries/Init.xml not found in ${script_dir}." >&2
  exit 1
fi

for command in git svn; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Error: ${command} is required but was not found in PATH." >&2
    exit 1
  fi
done

# PowerShell example:
# cd "C:\Users\Max\Documents\_dev_\BetterCooldownManager"; & "C:\Program Files\Git\bin\bash.exe" ./install-deps.sh

staging_dir="$(mktemp -d "${script_dir}/.install-deps.XXXXXX")"
staged_libraries="${staging_dir}/Libraries"
mkdir -p "${staged_libraries}/Ace3"
cp "${libraries_dir}/Init.xml" "${staged_libraries}/Init.xml"
git clone --depth 1 --branch main https://github.com/Silverbrit/LibSharedCanvas.git "${staged_libraries}/LibSharedCanvas-1.0"

svn export https://repos.curseforge.com/wow/ace3/trunk/AceAddon-3.0 "${staged_libraries}/Ace3/AceAddon-3.0"
svn export https://repos.curseforge.com/wow/ace3/trunk/AceDB-3.0 "${staged_libraries}/Ace3/AceDB-3.0"
svn export https://repos.curseforge.com/wow/ace3/trunk/AceLocale-3.0 "${staged_libraries}/Ace3/AceLocale-3.0"
svn export https://repos.curseforge.com/wow/ace3/trunk/AceSerializer-3.0 "${staged_libraries}/Ace3/AceSerializer-3.0"
svn export https://repos.curseforge.com/wow/callbackhandler/trunk/CallbackHandler-1.0 "${staged_libraries}/CallbackHandler-1.0"
svn export https://repos.curseforge.com/wow/libstub/trunk "${staged_libraries}/LibStub"
svn export https://repos.curseforge.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0 "${staged_libraries}/LibSharedMedia-3.0"

git clone --depth 1 https://github.com/SafeteeWoW/LibDeflate.git "${staged_libraries}/LibDeflate"
git clone --depth 1 --branch master https://github.com/Stanzilla/LibCustomGlow.git "${staged_libraries}/LibCustomGlow-1.0"
git clone --depth 1 --branch master https://github.com/AdiAddons/LibDualSpec-1.0.git "${staged_libraries}/LibDualSpec-1.0"
git clone --depth 1 --branch main https://github.com/plusmouse/LibEditModeOverride.git "${staged_libraries}/LibEditModeOverride"

# Keep a local PTR FrameXML snapshot for API and implementation verification.
staged_wow_ui_source="${staging_dir}/wow-ui-source"
git clone --depth 1 --filter=blob:none --branch ptr https://github.com/Gethe/wow-ui-source.git "${staged_wow_ui_source}"
find "${staged_wow_ui_source}" -mindepth 1 -maxdepth 1 ! -name Interface -exec rm -rf {} +

# Vendored dependencies should not retain nested repository metadata.
find "${staged_libraries}" -type d -name .git -prune -exec rm -rf {} +

rm -rf "${libraries_dir}"
mv "${staged_libraries}" "${libraries_dir}"

mkdir -p "${local_libraries_dir}"
rm -rf "${local_libraries_dir}/wow-ui-source"
mv "${staged_wow_ui_source}" "${local_libraries_dir}/wow-ui-source"

echo "BetterCooldownManager dependencies updated successfully."
