#!/bin/bash

homeward_tree_sha256() {
  local root="$1"
  (
    cd "$root"
    /usr/bin/find . -mindepth 1 -print |
      LC_ALL=C /usr/bin/sort |
      while IFS= read -r relative_path; do
        if [[ -L "$relative_path" ]]; then
          printf 'L %s %s %s\n' \
            "$(/usr/bin/stat -f '%Sp' "$relative_path")" \
            "$relative_path" \
            "$(/usr/bin/readlink "$relative_path")"
        elif [[ -f "$relative_path" ]]; then
          printf 'F %s %s %s\n' \
            "$(/usr/bin/stat -f '%Sp' "$relative_path")" \
            "$(shasum -a 256 "$relative_path" | awk '{print $1}')" \
            "$relative_path"
        elif [[ -d "$relative_path" ]]; then
          printf 'D %s %s\n' \
            "$(/usr/bin/stat -f '%Sp' "$relative_path")" \
            "$relative_path"
        fi
      done
  ) | shasum -a 256 | awk '{print $1}'
}

homeward_macho_uuid() {
  /usr/bin/dwarfdump --uuid "$1" |
    awk 'NR == 1 { print $2 }'
}

homeward_verify_dsym() {
  local binary="$1"
  local dsym="$2"
  local dsym_binary="$dsym/Contents/Resources/DWARF/Homeward"

  [[ -f "$dsym_binary" ]] || {
    printf 'Release dSYM binary is missing: %s\n' "$dsym_binary" >&2
    return 1
  }
  local binary_uuid
  local dsym_uuid
  binary_uuid="$(homeward_macho_uuid "$binary")"
  dsym_uuid="$(homeward_macho_uuid "$dsym_binary")"
  [[ -n "$binary_uuid" && "$binary_uuid" == "$dsym_uuid" ]] || {
    printf 'Release dSYM UUID does not match the app binary.\n' >&2
    return 1
  }
}
