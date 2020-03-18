jq -s '[ .[0] + .[1] | group_by(.apiproxy)[] | select(length > 1) | add ]'  all*.json



#jq -s 'include "joins"; joins(.apiproxy)' all*.json