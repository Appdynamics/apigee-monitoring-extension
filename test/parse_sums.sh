
  jq -r  '
                .[].stats.data[]
                | (.identifier.values[0]) as $identifier
                | (.metric[]
                      | select(.name == "sum(message_count)")
                      | .values
                      ) as $message_count
                | [$identifier, ($message_count | add)] | @tsv
    ' < metric_response.json | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//'