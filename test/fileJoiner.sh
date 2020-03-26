IOFileJoiner() {
  # arg {1} = file2 - the smaller content, {2} = file 1 the super set file, {3} = output
  awk '
  NR==FNR{ a[$1]=$2; next }
  { print $0, ($1 in a ? a[$1] : 0) }
' "${1}" "${2}" >"${3}"
}