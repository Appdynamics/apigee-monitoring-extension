
function JSONProccessor {
 jq '
  def myMathFunc:
    if (.name | test("^sum")) then
      {"\(.name)": (.values | add)}                           
    elif (.name | test("^avg|^global-avg")) then
      {"\(.name)": ((.values | add) / (.values | length)) }   
    elif (.name | test("^max")) then
      {"\(.name)": (.values | max) }   
    elif (.name | test("^min")) then
      {"\(.name)": (.values | min) } 
    else
      {"\(.name)": .values[]}                              
    end;

   [
  .Response.stats.data[] |
  .identifier.names[] as $name |
  .identifier.values[] as $val |
  {"\($name)": "\($val)"} + ([
    .metric[] | myMathFunc
  ] | add)
]
'  < ${1} > ${2}
}

JSONProccessor metric_response.json mmm.json
