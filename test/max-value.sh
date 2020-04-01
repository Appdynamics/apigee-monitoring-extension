 #now it's time for the fun bit that I always dread:)
        jq -r '
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
                   | (.metric[]
                      | select(.name == "min(request_processing_latency)")
                      | .values | min
                      ) as $min_request_processing_latency
                   | (.metric[]
                      | select(.name == "max(request_processing_latency)")
                      | .values | max
                      ) as $max_request_processing_latency
                   | (.metric[]
                      | select(.name == "max(target_response_time)")
                      | .values | max
                      ) as $max_target_response_time
                   | (.metric[]
                      | select(.name == "min(target_response_time)")
                      | .values | min
                      ) as $min_target_response_time
                   | (.metric[]
                      | select(.name == "min(total_response_time)")
                      | .values | min
                      ) as $min_total_response_time
                   | (.metric[]
                      | select(.name == "max(total_response_time)")
                      | .values | max
                      ) as $max_total_response_time
                   | (.metric[]
                      | select(.name == "sum(policy_error)")
                      | .values
                      ) as $sum_policy_error
                   | (.metric[]
                      | select(.name == "sum(target_error)")
                      | .values
                      ) as $sum_target_error
                | $identifier | gsub("( ? )"; ""), $global_avg_total_response_time, $global_avg_request_processing_latency,$global_avg_target_response_time,
                ($message_count | add),($error_count | add),($avg_total_response_time | add)/ ($avg_total_response_time | length),
                ($avg_target_response_time | add)/ ($avg_target_response_time | length),
                ($avg_request_processing_latency | add)/ ($avg_request_processing_latency | length),
                ($min_request_processing_latency),
                ($max_request_processing_latency),
                ($max_target_response_time),
                ($min_target_response_time),
                ($min_total_response_time),
                ($max_total_response_time),
                ($sum_policy_error | add),($sum_target_error | add)
              ' <${metric_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_response.out
