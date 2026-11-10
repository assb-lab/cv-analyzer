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

# Create the replacement first so a Finder failure leaves existing entries intact.
if [[ -d "$alias_path" && ! -L "$alias_path" ]]; then
    echo "エイリアスの置き場所がディレクトリです: ${alias_path}" >&2
    exit 1
fi

printf 'バージョン: %s\nエイリアス: %s\n参照先: %s\n' "$version" "$alias_path" "$source_ipf"
temp_dir="$(mktemp -d "${procedures_dir}/.cva-alias.XXXXXX")"
temp_alias="${temp_dir}/${alias_name}"
cleanup() {
    rm -f -- "$temp_alias"
    rmdir -- "$temp_dir" 2>/dev/null || true
}
trap cleanup EXIT
if ! osascript - "$source_ipf" "$temp_dir" "$alias_name" >/dev/null <<'APPLESCRIPT'
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
    echo "Finder エイリアスの作成に失敗しました。既存の項目は変更していません。" >&2
    exit 1
fi
if [[ ! -f "$temp_alias" ]]; then
    echo "作成したエイリアスを確認できません。既存の項目は変更していません。" >&2
    exit 1
fi

# Replace this version and remove other versioned CV Analyzer entries only.
mv -f -- "$temp_alias" "$alias_path"
while IFS= read -r -d '' path; do
    name="${path##*/}"
    if [[ "$name" == "$alias_name" || "$path" == "$source_ipf" ]]; then
        continue
    fi
    if [[ ! "$name" =~ ^CVAnalyzer_v_[0-9]+_[0-9]+_[0-9]+\.ipf$ ]]; then
        continue
    fi
    if [[ -d "$path" && ! -L "$path" ]]; then
        echo "ディレクトリは削除しません: ${path}" >&2
        continue
    fi
    rm -f -- "$path"
    printf '旧バージョンを削除しました: %s\n' "$path"
done < <(find "$procedures_dir" -maxdepth 1 -name 'CVAnalyzer_v_*.ipf' -print0)

printf 'エイリアスを作成しました: %s\n' "$alias_path"
