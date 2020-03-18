 jq  -r '
                .[].stats.data[]
                | (.identifier.values[0]) as $identifier
                | (.metric[]
                    | select(.name == "global-avg-total_response_time")
                    | .values
                    )  as $global_avg_total_response_time
                | (.metric[]
                    | select(.name == "global-avg-request_processing_latency")
                    | .values
                    ) as $global_avg_request_processing_latency
                  | (.metric[]
                      | select(.name == "global-avg-target_response_time")
                      | .values
                      ) as $global_avg_target_response_time
                  | (.metric[]
                      | select(.name == "sum(message_count)")
                      | .values
                      ) as $message_count
                  | (.metric[]
                      | select(.name == "sum(is_error)")
                      | .values
                      ) as $error_count
                  | (.metric[]
                      | select(.name == "avg(total_response_time)")
                      | .values
                      ) as $avg_total_response_time
                  | (.metric[]
                      | select(.name == "avg(target_response_time)")
                      | .values
                      ) as $avg_target_response_time
                  | (.metric[]
                      | select(.name == "avg(request_processing_latency)")
                      | .values
                      ) as $avg_request_processing_latency
                |  $identifier | gsub("( ? )"; ""), $global_avg_total_response_time, $global_avg_request_processing_latency,$global_avg_target_response_time,
                ($message_count | add),($error_count | add),($avg_total_response_time | add)/ ($avg_total_response_time | length),
                ($avg_target_response_time | add)/ ($avg_target_response_time | length),
                ($avg_request_processing_latency | add)/ ($avg_request_processing_latency | length)
              '< ~/Downloads/response.json | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//'