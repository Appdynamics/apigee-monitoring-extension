 jq  '.[].stats.data[]
    | [.identifier.names, .identifier.values]
    | transpose
    | map({(.[0]): .[1]})
    | add     
    ' < response.json
