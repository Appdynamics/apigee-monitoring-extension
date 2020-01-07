#!/bin/sh

#Send Analytics Events to AppD
schema_name="apigee_error_codes"
schema_template="analytics/schema.json"
markerfile="analytics/schema.markerfile"

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

if [[ ! -f "${markerfile}" ]]; then
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

#normalise the JSON payload from Apigee response to match AppDynamics Schema. 
 processed_analytics=$(
    jq  '.[].stats.data[]
    | [.identifier.names, .identifier.values]
    | transpose
    | map({(.[0]): .[1]})
    | add 
    ' < ${curl_output}  | awk '/}/{print $0 ","; next}1' | sed '$ s/.$//' 
 )

payload="[${processed_analytics}]"
curl_response_code=$(curl -v -X POST "${analytics_ep}/events/publish/$schema_name" -H"X-Events-API-AccountName:${global_account_name}" -H"X-Events-API-Key:${analytics_key}" -H"Content-type: application/vnd.appd.events+json;v=2" -d "${payload}" -s -w "%{http_code}" $proxy_details)

echo "response code = $curl_response_code" 

 if [ "${curl_response_code}" -eq 200 ]; then
       msg="Succesfully sent analytics event to AppDynamics."
       echo "${msg}"
       echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg}" >> ${log_path}
 else 
       msg="Response code: ${curl_response_code}. Failed to send analytics event to AppDynamics, please ensure your credentials are correct"
       echo "${msg}"
       echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >> ${log_path}
fi


