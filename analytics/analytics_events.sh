#!/bin/sh

#Send Analytics Events to AppD
schema_template="analytics/schema.json"
markerfile="analytics/schema.markerfile" # The existence of this file will prevent the creation of a new schema. Delete it if a new schema  is required.
biq_request_payload="biq_request_payload.json"
schema_name=$(jq -r  '.analytics_details[].schema_name' <  ${apigee_conf_file})

analytics_ep=$(jq -r  '.analytics_details[].analytics_endpoint' < ${apigee_conf_file})
analytics_key=$(jq -r  '.analytics_details[].analytics_key' <  ${apigee_conf_file})
global_account_name=$(jq -r  '.analytics_details[].global_account_name' <  ${apigee_conf_file})
proxy_url=$(jq -r  '.analytics_details[].proxy_url' <  ${apigee_conf_file})
proxy_port=$(jq -r  '.analytics_details[].proxy_port' <  ${apigee_conf_file})

echo "endpoint - $analytics_ep "
echo  "key -  ***"
echo "global account name - $global_account_name"
echo "Proxy URL - $proxy_url"
echo "Proxy port - $proxy_port"
echo "schema_name - $schema_name"

 if [ -z $analytics_ep ] || [ -z $analytics_key ] || [ -z $global_account_name ] ; then 
     msg=" analytics endpoint, analytics key and global account name must be filled in the config.json file - if BiQ is enabled"
     echo "${msg}"
     echo "[$(date '+%d-%m-%Y %H:%M:%S')] [FATAL] ${msg}" >> ${log_path}
     exit 0
 fi  

 if [ -z $proxy_url ] || [ -z $proxy_port ]; then 
    echo "Not Using proxy" 
    proxy_details=""
  else 
   echo "Using proxy - $proxy_url:$proxy_port"
     proxy_details="-x $proxy_url:$proxy_port"
 fi

if [ ! -f "${markerfile}" ]; then
   curl_response_code=$(curl -X POST "${analytics_ep}/events/schema/$schema_name" -H"X-Events-API-AccountName:${global_account_name}" -H"X-Events-API-Key:${analytics_key}" -H"Content-type: application/vnd.appd.events+json;v=2" --data @${schema_template} -s -w "%{http_code}" $proxy_details)
   echo "Create Schema response code $curl_response_code" 

   if [ "${curl_response_code}" -eq 201 ]; then
       msg=" The  ${schema_name} schema was succesfully created. And marker file was also created- this file ensures the post request is made once"
       echo "${msg}"
       echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg}" >> ${log_path} 
       touch ${markerfile}
   fi
else
    echo "==>Marker file exist. This means $schema_name already exist. Skipping"  
fi

#normalize the JSON payload from Apigee response to match AppDynamics Schema. 

 if [ "${found_4xx}" = "true" ] && [ "${found_5xx}" = "true" ]; then
    echo "merging all 3 json files"
    jq -s '[ .[0] + .[1] | group_by(.apiproxy)[]  | add ]'  ${biq_4xx_metrics} ${biq_5xx_metrics}  > temp_${biq_request_payload}
    sleep 1
    jq -s '[ .[0] + .[1] | group_by(.apiproxy)[]  | add ]'  temp_${biq_request_payload} ${biq_perf_metrics}  > ${biq_request_payload}

    rm temp_${biq_request_payload}
 fi

if [ "${found_4xx}" = "true" ] && [ "${found_5xx}" = "false" ]; then
    echo "merging only 4xx file"
     jq -s '[ .[0] + .[1] | group_by(.apiproxy)[]  | add ]' ${biq_perf_metrics} ${biq_4xx_metrics}  > ${biq_request_payload}
fi

if [ "${found_4xx}" = "false" ] && [ "${found_5xx}" = "true" ]; then
    echo "merging only 5xx file"
    jq -s '[ .[0] + .[1] | group_by(.apiproxy)[]  | add ]' ${biq_perf_metrics} ${biq_5xx_metrics}  > ${biq_request_payload}
fi

if [ "${found_4xx}" = "false" ] && [ "${found_5xx}" = "false" ]; then
   echo "No 5xx or 4xx error - nothing to merge"
   biq_request_payload=${biq_request_payload}
fi
# if [ "${found_4xx}" = "true" ] || [ "${found_5xx}" = "true" ]; then
#     echo "4xx or 5xx is found..merging json"
#     jq -s '[ .[0] + .[1] | group_by(.apiproxy)[]  | add ]'  biq_prepped*.json  > ${biq_request_payload}    
# else
#     echo "No 4xx or 5xx is found..nothing to merge"
#     biq_request_payload = ${biq_perf_metrics}
# fi

#decorate biq payload
cat ${biq_request_payload} | sed 's/min(/min_/g; s/max(/max_/g; s/is_error/error_count/g; s/)//g;s/sum(//g; s/)//g; s/avg(//g; s/-/_/g' > "decorated_${biq_request_payload}"

biq_request_payload="decorated_${biq_request_payload}"

if [ ! -f "${biq_request_payload}" ]; then
    msg="${biq_request_payload} does not exist. No metric will be sent to Apigee. "
    echo "${msg}"
    echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg} " >>${log_path}
    exit 0
else
    curl_response_code=$(curl -X POST "${analytics_ep}/events/publish/$schema_name" -H"X-Events-API-AccountName:${global_account_name}" -H"X-Events-API-Key:${analytics_key}" -H"Content-type:application/vnd.appd.events+json;v=2" -H"Accept:application/json"  -d "$(cat ${biq_request_payload})" -s -w "%{http_code}" $proxy_details)
    echo "response code = $curl_response_code" 
    if [ "${curl_response_code}" -eq 200 ]; then
        msg="Succesfully sent analytics event to AppDynamics."
        echo "${msg}"
        echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg}" >> ${log_path}
        #clean up  
        rm biq_*.json decorated_biq_*.json raw_biq_prepped*.json
    else 
        msg="Response code: ${curl_response_code}. Failed to send analytics event to AppDynamics, please ensure your credentials are correct"
        echo "${msg}"
        echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >> ${log_path}

        # No need to clean up, leave files to help support with troubleshooting 
    fi

fi
