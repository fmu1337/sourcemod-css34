#!/usr/bin/env bash
# usage: floor2.sh <dir> -> per ELF: max GLIBC, max GLIBCXX, CXXABI, GCC, NEEDED, # exported dynsyms, syms requiring > $THR
d="$1"; THR="${THR:-2.17}"
find "$d" -type f \( -name '*.so' -o -name 'spcomp*' -o -name 'srcds*' \) | sort | while read -r f; do
  file -b "$f" | grep -q ELF || continue
  T=$(objdump -T "$f" 2>/dev/null)
  vers=$(echo "$T" | grep -oE '(GLIBC|GLIBCXX|CXXABI|GCC)_[0-9.]+' | sort -uV)
  g=$(echo "$vers" | grep '^GLIBC_' | sort -V | tail -1)
  x=$(echo "$vers" | grep -E '^(GLIBCXX|CXXABI)_' | sort -V | tr '\n' ' ')
  n=$(readelf -d "$f" | grep NEEDED | grep -oE '\[[^]]+\]' | tr -d '[]' | tr '\n' ',')
  ex=$(echo "$T" | awk '$0 !~ /\*UND\*/ && ($2=="g"||$2=="w"||$3=="g") ' | wc -l)
  hi=$(echo "$T" | awk '/\*UND\*/ {print}' | grep -oE 'GLIBC_2\.[0-9]+(\.[0-9]+)?\)? +[A-Za-z0-9_]+' | sed 's/)//' | awk -v t="$THR" '{split($1,a,"_"); v=a[2]; if (system("[ \"$(printf \"%s\\n%s\\n\" " v " " t " | sort -V | tail -1)\" != " t " ]")==0) print $2"@"v}' | sort -u | tr '\n' ' ')
  echo "${f#$d/} | ${g:-none} | ${x} | NEEDED=$n | exports=$ex | >$THR: $hi"
done
