#!/bin/bash
# Place a Finder alias to this checkout in Igor Pro 8 User Files (macOS).
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "このスクリプトは macOS 専用です。" >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
source_ipf="${repo_root}/CVAnalyzer.ipf"
procedures_dir="${CVA_IGOR_PROCEDURES_DIR:-${HOME}/Documents/WaveMetrics/Igor Pro 8 User Files/Igor Procedures}"

if [[ ! -f "$source_ipf" ]]; then
    echo "手順ファイルが見つかりません: ${source_ipf}" >&2
    exit 1
fi
if [[ ! -d "$procedures_dir" ]]; then
    echo "Igor Procedures フォルダが見つかりません: ${procedures_dir}" >&2
    exit 1
fi
procedures_dir="$(cd "$procedures_dir" && pwd -P)"

# The numeric Igor pragma cannot represent a three-component SemVer.
version="$(awk '$1 == "//" && $2 == "Semantic" && $3 == "version:" { print $4 }' "$source_ipf")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "SemVer を読み取れませんでした: ${source_ipf}" >&2
    exit 1
fi
alias_name="CVAnalyzer_v_${version//./_}.ipf"
alias_path="${procedures_dir}/${alias_name}"

# Never remove or replace an existing file, alias, symlink or directory.
if [[ -e "$alias_path" || -L "$alias_path" ]]; then
    echo "同名の項目が存在するため作成を中止します: ${alias_path}" >&2
    exit 1
fi

printf 'バージョン: %s\nエイリアス: %s\n参照先: %s\n' "$version" "$alias_path" "$source_ipf"
if ! osascript - "$source_ipf" "$procedures_dir" "$alias_name" >/dev/null <<'APPLESCRIPT'
on run argv
    set sourcePath to item 1 of argv
    set destPath to item 2 of argv
    set aliasName to item 3 of argv
    tell application "Finder"
        set sourceFile to POSIX file sourcePath as alias
        set destFolder to POSIX file destPath as alias
        make new alias file at destFolder to sourceFile with properties {name:aliasName}
    end tell
end run
APPLESCRIPT
then
    echo "Finder エイリアスの作成に失敗しました。" >&2
    exit 1
fi
if [[ ! -f "$alias_path" ]]; then
    echo "エイリアスを確認できません: ${alias_path}" >&2
    exit 1
fi
printf 'エイリアスを作成しました: %s\n' "$alias_path"
