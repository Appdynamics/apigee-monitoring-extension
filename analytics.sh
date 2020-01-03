
analytics_ep=$(jq -r  '.analytics_details[].analytics_endpoint' < config.json)

analytics_key=$(jq -r  '.analytics_details[].analytics_key' < config.json)

global_account_name=$(jq -r  '.analytics_details[].global_account_name' < config.json)

echo $analytics_ep
echo $analytics_key
echo $global_account_name

 if [ -z $(_ijq '.host_url') ] or [ -z $analytics_key ] && [ -z $global_account_name ] ; then 

schema_name="apigee_error_codes"
schema_template="schema.json"
markerfile="${schema_name}.markerfile"
log_path="../../../logs/apigee-monitor.log"

if [ ! -f "${markerfile}" ]; then
   curl_response_code=$(curl -X POST "${analytics_ep}/events/schema/$schema_name" -H"X-Events-API-AccountName:${global_account_name}" -H"X-Events-API-Key:${analytics_key}" -H"Content-type: application/vnd.appd.events+json;v=2" --data @${schema_template} -s -w "%{http_code}")
   echo "Create Schema response code $curl_response_code" 

   if [ "${curl_response_code}" -eq 201 ]; then
       touch ${markerfile}
       msg=" The  ${schema_name} schema was succesfully created. And marker file was also created- this file ensures the post request is made once"
       echo "${msg}"
       echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >> ${log_path}
   fi

else
    echo "==>Marker file exist. This means $schema_name already exist"  
 fi

exit

jq  '.[].stats.data[]
| [.identifier.names, .identifier.values]
| transpose
| map({(.[0]): .[1]})
| add 
' < response.json  | awk '/}/{print $0 ","; next}1' | sed '$ s/.$//' > out.out 

payload="["$(cat out.out)"]"

payload="["$(cat out.out)"]"

curl_response_code=$(curl -X POST "${analytics_ep}/events/publish/$schema_name" -H"X-Events-API-AccountName:${global_account_name}" -H"X-Events-API-Key:${analytics_key}" -H"Content-type: application/vnd.appd.events+json;v=2" -d "${payload}" -s -w "%{http_code}")

echo "response code = $curl_response_code" 



