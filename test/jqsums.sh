#!/bin/sh
jq '

def summarize:
    if .name | test("^sum", "") then
      {"\(.name)": (.values | add)}                           # sum
    elif .name | test("^avg|^global-avg", "") then
      {"\(.name)": ((.values | add) / (.values | length)) }   # average
    else
      {"\(.name)": .values[]}                                 # pass through unmodified
    end;

[
  .Response.stats.data[] |
  .identifier.names[] as $name |
  .identifier.values[] as $val |
  {"\($name)": "\($val)"} + ([
    .metric[] | summarize
  ] | add)
]
' < ../metric_response.json 
