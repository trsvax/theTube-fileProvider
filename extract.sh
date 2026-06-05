#!/bin/zsh
# Extract # src blocks from markdown files into out/
# Usage: ./extract.sh

OUT_DIR="out"
/bin/rm -rf "$OUT_DIR"
/bin/mkdir -p "$OUT_DIR"

typeset -A FILES

for md in src/[0-9]*.md(N); do
  current_file=""
  in_block=false

  while IFS= read -r line; do
    if [[ "$in_block" == true ]]; then
      if [[ "$line" == '```' ]]; then
        in_block=false
      else
        FILES[$current_file]+="$line
"
      fi
    elif [[ "$line" =~ '```[a-z]+ # src (.+)' ]]; then
      current_file="${match[1]}"
      in_block=true
    fi
  done < "$md"
done

count=0
for path in ${(k)FILES}; do
  dir="$OUT_DIR/${path%/*}"
  [[ "$dir" != "$OUT_DIR/$path" ]] && /bin/mkdir -p "$dir"
  printf '%s' "${FILES[$path]}" > "$OUT_DIR/$path"
  echo "  $path"
  count=$((count + 1))
done

echo ""
echo "Extracted $count files to $OUT_DIR/"
