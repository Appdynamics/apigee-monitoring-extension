#!/bin/sh

#Author : Israel.Ogbole@appdynamics.com
version="[ApigeeMonitore v2.6.0 Build Date 2020-03-18 12:59]"

[[ "$(command -v jq)" ]] || { echo "jq is not installed, please download it from - https://stedolan.github.io/jq/download/ and try again after installing it. Aborting.." 1>&2 ; sleep 5; exit 1; }

#This extension sends the following Apigee metrics to AppDynamics
# 1) Response Time:	Total number of milliseconds it took to respond to a call. This time includes the Apigee API proxy overhead and your target server time.
# 2) Target Response Time:	Number of milliseconds it took your target server to respond to a call. This number tells you how your own servers are behaving.
# 3) Request Processing Latency:	Number of milliseconds from the time when a call reaches the selected API proxy to the time when Apigee sends the call to your target server.
# 4) Response Processing Latency : Number of milliseconds from the time when the API proxy receives your target server’s response to the time when Apigee sends the response to the original caller.
# Add the request and response latencies to calculate the final overhead the API proxy added to the call.
# 5) Total Message Count - The number of recorded API requests for each API proxy
# 6) Total Error Count - The total number of times API proxies failed over the specified time period. Proxy failure can occur when a policy fails or when there's a runtime failure, such as a 404 or 503 from the target service.
# 7)  API Proxy HTTP Response code - HTTP response Error codes (4xx, 5xxx, etc) - https://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
# 8) Target Response code - API target response code
#Refs:
#Explanation of metrics:
# https://docs.apigee.com/api-platform/analytics/analytics-reference
# https://docs.apigee.com/analytics-services/content/latency-analysis-dashboard
#Meric API : https://docs.apigee.com/analytics-services/content/latency-analysis-dashboard

# onpremise installation API URL is different from cloud, onpremise uses port 8080 in most cases i.e
#Ref : https://community.apigee.com/questions/3170/edge-management-api-url-for-on-premises.html
#host_name="https://api.enterprise.apigee.com" # for onpremise installation use http(s)://<IP>:8080
#The organization and environments variable names returned 404 for an onpremise installation of apigee. Changing it to  'o' and 'e' in the curl cmd worked. I don't know why.

#This will create metrics in specific Tier/Component. Make sure to replace <tier_id> with the appropriate one from your environment.
#To find the tier_id in your environment, please follow the screenshot https://docs.appdynamics.com/display/PRO42/Build+a+Monitoring+Extension+Using+Java?preview=/34272441/34413993/componentid.png
#metric_prefix="Server|Component:<tier-name>|Custom Metrics|Apigee"
#This will create metrics in all tiers of your business application
#metric_prefix="Custom Metrics|Apigee"  #Read this value is now from config.json
metric_base="Proxies"
proxy_conf_file_path="apiproxy.conf"
apigee_conf_file="testconfig.json"
log_path="../../logs/apigee-monitor.log"

real_time=true
timeUnit="minute" #A value of second, minute, hour, day, week, month, quarter, year, decade, century, millennium.
apiproxy_names=""
#dimensions="apiproxy,response_status_code,target_response_code,api_product,ax_cache_source,client_id,ax_resolved_client_ip,client_id,developer_app,environment,organization,proxy_basepath,proxy_pathsuffix,apiproxy_revision,virtual_host,ax_ua_device_category,ax_ua_os_family,ax_ua_os_version,proxy_client_ip,ax_true_client_ip,client_ip,request_path,request_uri,request_verb,useragent,ax_ua_agent_family,ax_ua_agent_type,ax_ua_agent_version,target_basepath,target_host,target_ip,target_url,x_forwarded_for_ip,ax_day_of_week,ax_month_of_year,ax_hour_of_day,ax_dn_region,ax_dn_region,client_ip"
dimensions="apiproxy"

metric_curl_output="metric_response.json"
fourxx_curl_output="4xx_response.json"
fivexx_curl_output="5xx_response.json"

#analytics output 

biq_perf_metrics="biq_prepped_perf_metrics.json"
biq_5xx_metrics="biq_prepped_5xx_metrics.json"
biq_4xx_metrics="biq_prepped_4xx_metrics.json"

#initialize reponse codes
fourxx_curl_response_code=""
fivexx_curl_response_code=""
metric_curl_response_code=""

merged_metric_file="merged_metric_file.out"

found_4xx="false"
found_5xx="false"

#takes 3 params in this order 1. requst url 2. username 3. password
IOcURL() {
  #clean up any orphaned file from the previous run.
  #rm jq_processed_response.out metrified_response.out jq_processed_status_code.out
  [ -f "${4}" ] && rm "${4}"
  echo ""
  echo "curl ${1} -u ${2}:******"
  echo ""
  # for added security, store your password in a file, and cat it like this $(cat .password), otherwise password will be visible in bash history
  # or use -n (.netrc) instead
  #metric_curl_response_code=$(curl -u ${apigee_username}:${apigee_password} -s -w "%{http_code}" -o "${metric_curl_output}" -X GET "${1}")
  response=$(curl -u "${2}":"${3}" -s -w "%{http_code}" -o "${4}" -X GET "${1}")
}

IOFileJoiner() {
  # arg {1} = file2 - the smaller content, {2} = file 1 the super set file, {3} = output
  awk '
  NR==FNR{ a[$1]=$2; next }
  { print $0, ($1 in a ? a[$1] : 0) }
' "${1}" "${2}" >"${3}"
}

function JSONProccessor(){
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
'  < ${1} > ${2}
}

#Initialise log with version
echo "{$version}" >>${log_path}

if [ ! -f "${proxy_conf_file_path}" ]; then
  msg="${proxy_conf_file_path} does not exist. \n This file is required for this extension to work.\
    Create a line delimited list of your api proxy names i.e one proxy per line and ensure you hit enter"
  echo "${msg}"
  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >>${log_path}
  exit 1
fi

if [ ! -f "${apigee_conf_file}" ]; then
  msg="${apigee_conf_file} does not exist. This file is required for this extension to work."
  echo "${msg}"
  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg} " >>${log_path}
  exit 1
fi

#Set Metric Prefix from config

metric_prefix=$(jq -r '.metric_prefix' <${apigee_conf_file})
query_interval=$(jq -r '.query_interval' <${apigee_conf_file}) #in seconds. Best to leave this at 1.5 mins for better accuracy based on my test result. There's a slight lag in the way apigee computes 4xx and 5xx errors stats. 
query_limit=$(jq -r '.query_limit' <${apigee_conf_file})

echo "Setting Metric Prefix - $metric_prefix "

#read proxy names from the conf file
while read -r proxy_name || [ -n "$proxy_name" ]; do
  #Fix for support ticket : #223734 - Old versions of Apigee apparantly allows spaces in the proxy names
  #URL encode the spaces - before sending the curl request, then use jq gsub to strip the spaces from the
  # the indentifier string
  echo "Raw Proxy Value - ${proxy_name}"
  proxy_name=$(echo "$proxy_name" | sed 's/ /%20/g')
  echo "URL Encoded Proxy Value - ${proxy_name}"
  #concatenate  proxy_names - seperated by commas and put them in between single qoutes ''
  apiproxy_names="${apiproxy_names}'${proxy_name}',"
done <"${proxy_conf_file_path}"

#remove the last comma in the line with sed                      and the last whitespace
apiproxy_names=$(echo "${apiproxy_names}" | sed 's/\(.*\),/\1 /' | awk '{$1=$1}1')

echo "==> Will use the following proxies if 'use_proxy_filter' is set to true in the config.json file : ${apiproxy_names}"

echo ""
#Use this if you're using Mac OS
#minutes_ago=$(date -r $(( $(date +%s) - 600 )) | awk '{print $4}')
#time_now=$(date +"%T")
#today=$(date +"%m/%d/%Y")
#to_range=$(echo ${today}+${time_now})
#from_range=$(echo ${today}+${minutes_ago})

#or this if you're using Ubuntu, CentOS or Redhat
to_range=$(date +%m/%d/%Y+%H:%M:%S)
from_range=$(date +%m/%d/%Y+%H:%M:%S --date="$query_interval seconds ago")

echo "==> Time range: from ${from_range} to ${to_range}"

# Read BiQ flag from config file
enable_biq=$(jq -r '.enable_BiQ' <${apigee_conf_file})

echo "==>Enable BiQ for metrics"

for row in $(cat ${apigee_conf_file} | jq -r ' .connection_details[] | @base64'); do
  _ijq() {
    echo ${row} | base64 --decode | jq -r ${1}
  }

  host_name=$(_ijq '.host_url')
  environments=$(_ijq '.env')
  organization=$(_ijq '.org')

  if [ -n "${host_name}" ] && [ -n "${environments}" ] && [ -n "${organization}" ]; then
    username=$(_ijq '.username')
    password=$(_ijq '.password')
    server_friendly_name=$(_ijq '.server_friendly_name')
    use_proxy_filter=$(_ijq '.use_proxy_filter')

    if [ -z "${server_friendly_name}" ]; then
      server_friendly_name=$(echo "${host_name}" | sed 's~http[s]*://~~g')
    fi

    echo "===> Processing host_name:${host_name} ~~ env:${environments}  ~~ org:${organization} ~  \
      server_friendly_name : ${server_friendly_name} ~ use_proxy_filter : $use_proxy_filter ~ username : ${username}  ~ password : ****** "

    base_url="${host_name}/v1/organizations"

    fourxx="&filter=(response_status_code%20ge%20400%20and%20response_status_code%20le%20499)"
    fivexx="&filter=(response_status_code%20ge%20500%20and%20response_status_code%20le%20599)"

    fourxx_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20response_status_code%20ge%20400%20and%20response_status_code%20le%20499)"
    fivexx_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20response_status_code%20ge%20500%20and%20response_status_code%20le%20599)"
    proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names})"

    req="${base_url}/${organization}/environments/${environments}/stats/${dimensions}?_optimized=js&realtime=${real_time}&limit=${query_limit}&select=sum(message_count),avg(total_response_time),avg(target_response_time),avg(request_processing_latency),sum(is_error)&sort=DESC&sortby=sum(message_count),avg(total_response_time),sum(is_error)&timeRange=${from_range}~${to_range}&timeUnit=${timeUnit}&tsAscending=true"

    #proxy_filter_req="${base_url}/${organization}/environments/${environments}/stats/${dimensions}?_optimized=js&realtime=${real_time}&limit=${query_limit}&select=sum(message_count),avg(total_response_time),avg(target_response_time),avg(request_processing_latency),sum(is_error)&sort=DESC&sortby=sum(message_count),avg(total_response_time),sum(is_error)&timeRange=${from_range}~${to_range}&timeUnit=${timeUnit}&tsAscending=true"

    #https://api.enterprise.apigee.com/v1/organizations/iogbole-70230-eval/environments/prod/stats/apiproxy,response_status_code,target_response_code?_optimized=js&select=sum(message_count),sum(is_error),avg(total_response_time),avg(target_response_time)&sort=DESC&sortby=sum(message_count),sum(is_error),avg(total_response_time),avg(target_response_time)&timeRange=12/18/2019+00:00:15~12/19/2019+00:50:15"
    #send the request to Apigee
    #use ${filtered_req} if you want to use the filtered request and ${req} for unfiltered
    if [ "${use_proxy_filter}" = "true" ]; then
      echo "Using filtered request"
      echo "Metric request.."
      IOcURL "${req}${proxy_filter}" "${username}" "${password}" ${metric_curl_output}
      metric_curl_response_code=${response}
      echo "metric_curl_response_code==>$metric_curl_response_code"
      echo "4xx  request..."
      IOcURL "${req}${fourxx_proxy_filter}" "${username}" "${password}" ${fourxx_curl_output}
      fourxx_curl_response_code=${response}
      echo "fourxx_curl_response_code==> ${fourxx_curl_response_code}"
      echo "5xx request..."
      IOcURL "${req}${fivexx_proxy_filter}" "${username}" "${password}" ${fivexx_curl_output}
      fivexx_curl_response_code=${response}
      echo "fivexx_curl_response_code==>${fivexx_curl_response_code}"
    else
      echo "Using un-filtered request - collecting all proxy information"
      echo "Metric request.."
      IOcURL "${req}" "${username}" "${password}" ${metric_curl_output}
      metric_curl_response_code=${response}
      echo "metric_curl_response_code==>$metric_curl_response_code"
      echo "4xx  request..."
      IOcURL "${req}${fourxx}" "${username}" "${password}" ${fourxx_curl_output}
      fourxx_curl_response_code=${response}
      echo "fourxx_curl_response_code==> ${fourxx_curl_response_code}"
      echo "5xx request..."
      IOcURL "${req}${fivexx}" "${username}" "${password}" ${fivexx_curl_output}
      fivexx_curl_response_code=${response}
      echo "fivexx_curl_response_code==>${fivexx_curl_response_code}"
    fi

    if [ "${metric_curl_response_code}" -ne 200 ]; then
      msg="The request failed with ${metric_curl_response_code} response code.\nThe requested URL is: ${req} \n  
          $(cat ${metric_curl_output}) \n"
      echo "${msg}"
      echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >>${log_path}

    else

      if [ ! -f "${metric_curl_output}" ]; then
        msg="The output of the cURL request wasn't saved. Please ensure that $(whoami) user has write acccess to $(pwd). Exiting..."
        echo "${msg}"
        echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >>${log_path}
        exit 0
      fi
      echo "DEBUG: Processing ${metric_curl_output} collection. "
      #check if identifier string is present in the output
      output_finder="identifier" # this variable got to be unique for each curl request as bash handles all variables as global.
      if ! grep -q ${output_finder} "${metric_curl_output}"; then
        msg="The request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
              Please make sure there is traffic - from ${from_range} to ${to_range}"
        echo "${msg}"
        echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
        msg="Skipping response processing for host_name:${host_name} ~~ env:${environments}  ~~ org:${organization}"
        echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
        echo "${msg}"
      else
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
                | $identifier | gsub("( ? )"; ""), $global_avg_total_response_time, $global_avg_request_processing_latency,$global_avg_target_response_time,
                ($message_count | add),($error_count | add),($avg_total_response_time | add)/ ($avg_total_response_time | length),
                ($avg_target_response_time | add)/ ($avg_target_response_time | length),
                ($avg_request_processing_latency | add)/ ($avg_request_processing_latency | length)
              ' <${metric_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_response.out

        #Process BiQ Data 
        JSONProccessor ${metric_curl_output} raw_${biq_perf_metrics}
        #Add Apigee Environment details to help distinguish data source in BiQ
        jq  --arg name "${server_friendly_name}" --arg env "${environments}"  --arg org "${organization}"  '.[]  += {"server_friendly_name":$name, "environment":$env, "organization":$org}' < raw_${biq_perf_metrics} > ${biq_perf_metrics}
        
        #1.Processing Performance metrics outputs.
        #tranpose the matrix of the metrics
        #a=identifier
        #b=global-avg-total_response_time
        #c=global-avg-request_processing_latency
        #d=global-avg-request_processing_latency
        #additional metrics - 19/12/2019
        #e=message_count
        #f=error_count
        #g=avg_total_response_time
        #h=avg_target_response_time
        #i=avg_request_processing_latency

        awk 'NF>0{a=$0;getline b; getline c; getline d; getline e; getline f; getline g; getline h; getline i;
                  print a FS b FS c FS d FS e FS f FS g FS h FS i}' jq_processed_response.out >metrified_response.out

        echo "DEBUG: Processing ${fourxx_curl_output} collections"

        finder_4xx="identifier"
        if ! grep -q ${finder_4xx} "${fourxx_curl_output}"; then
          msg="The 4xx request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
                this usually mean no proxy returned 4XX response code from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
          echo " 4xx does not exist. setting metrified_response.out as the final output"
          # merged_metric_file="metrified_response.out"
        else
          jq -r '
                    .[].stats.data[]
                    | (.identifier.values[0]) as $identifier
                    | (.metric[]
                          | select(.name == "sum(message_count)")
                          | .values
                          ) as $fourxx_count
                    | [$identifier | gsub("( ? )"; ""), ($fourxx_count | add)] | @tsv
                   ' <${fourxx_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_4xx_response.out

          found_4xx="true"

          #4xx BiQ Processor
          JSONProccessor ${fourxx_curl_output} biq_4xx_raw.json
          cat biq_4xx_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, four_xx: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_4xx_metrics}
          #  #Merge/Join jq_processed_4xx_response.out into jq_processed_response.out
          #  IOFileJoiner jq_processed_4xx_response.out metrified_response.out merged_with_4xx.out
        fi

        echo "DEBUG: Processing ${fivexx_curl_output} collections"
        finder_5xx="identifier"
        if ! grep -q ${finder_5xx} "${fivexx_curl_output}"; then
          msg="The 5xx request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
                this usually mean no proxy returned 4XX response code from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
          # #If 5xx does not exist....
          #  if [ -f "merged_with_4xx.out" ]; then
          #  #but 4xx exist, then use merged_with_4xx.out as the final file,
          #     echo " 4xx exist but 5xx does not exist. setting merged_with_4xx.out as the final output"
          #     merged_metric_file="merged_with_4xx.out"
          #   else
          #   # however if 4xx and 5xx does not exist, then use the main metrified_response.out file as the final file
          #     echo " 4xx and 5xx does not exist. setting metrified_response.out as the final output"
          #     merged_metric_file="metrified_response.out"
          #  fi
        else
          jq -r '
                    .[].stats.data[]
                    | (.identifier.values[0]) as $identifier
                    | (.metric[]
                          | select(.name == "sum(message_count)")
                          | .values
                          ) as $fivexx_count
                    | [$identifier | gsub("( ? )"; ""), ($fivexx_count | add)] | @tsv
                   ' <${fivexx_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_5xx_response.out
          found_5xx="true"
          #5xx BiQ Processor
          JSONProccessor ${fivexx_curl_output} biq_5xx_raw.json
          cat  biq_5xx_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, five_xx: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_5xx_metrics}
          # if [ -f "merged_with_4xx.out" ]; then
          #   echo "4xx and 5xx found... merging merged_with_4xx.out and jq_processed_5xx_response.out "
          #   # If 4xx error is found, this condition will be met, it will merge all 3 outputs (i.e main metrified_response.out file, 4xx and 5xx)
          #   IOFileJoiner jq_processed_5xx_response.out merged_with_4xx.out ${merged_metric_file}
          #  else
          #     # this condition will only be satisifed if 4xx does not exist, this will result in merging only
          #     # 5xx response to the main jq_processed_response.out file.
          #     echo "4xx not found, but 5xx exist... merging metrified_response.out and jq_processed_5xx_response.out "
          #     IOFileJoiner jq_processed_5xx_response.out metrified_response.out ${merged_metric_file}
          # fi
        fi

        generic_metric_path="name=${metric_prefix}|${server_friendly_name}|${metric_base}|${environments}"
        sum_of_messages=0
        sum_of_errors=0
        overrall_response_time=0
        i=0
        while read -r response_content; do
          identifier=$(echo "${response_content}" | awk '{print $1}')
          #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
          global_avg_total_response_time=$(echo "${response_content}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          global_avg_request_processing_latency=$(echo "${response_content}" | awk '{print $3}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          global_avg_target_response_time=$(echo "${response_content}" | awk '{print $4}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          #additional metrics - 19/12/2019
          message_count=$(echo "${response_content}" | awk '{print $5}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          error_count=$(echo "${response_content}" | awk '{print $6}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          avg_total_response_time=$(echo "${response_content}" | awk '{print $7}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          avg_target_response_time=$(echo "${response_content}" | awk '{print $8}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          avg_request_processing_latency=$(echo "${response_content}" | awk '{print $9}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          #parameterising the paths to make it easier to manager in the future
          name_path="${generic_metric_path}|${identifier}"
          echo "$name_path|Availability, value=1"
          echo "$name_path|Total Message Count, value=${message_count}"
          echo "$name_path|Total Error Count, value=${error_count}"
          echo "$name_path|Global Average Response Time, value=${global_avg_total_response_time}"
          echo "$name_path|Global Request Processing Latency, value=${global_avg_request_processing_latency}"
          echo "$name_path|Global Average Target Response Time, value=${global_avg_target_response_time}"
          echo "$name_path|Average Total Response Time, value=${avg_total_response_time}"
          echo "$name_path|Average Target Response Time, value=${avg_target_response_time}"
          echo "$name_path|Average Request Processing Latency, value=${avg_request_processing_latency}"

          sum_of_messages=$(($sum_of_messages + $message_count))
          sum_of_errors=$(($sum_of_errors + ${error_count}))
          overrall_response_time=$(($overrall_response_time + $avg_total_response_time))
          i=$(($i + 1))
        done <metrified_response.out

        avg=$(($overrall_response_time / $i))
        rounded_avg=$(echo ${avg} | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
        echo "$generic_metric_path|Overall Average Response Time, value=${rounded_avg}"
        echo "$generic_metric_path|Message Count Sum, value=${sum_of_messages}"
        echo "$generic_metric_path|Error Count Sum, value=${sum_of_errors}"

        #Processing 4xx metrics for AppDynamics
        if [ "${found_4xx}" = "true" ]; then
          sum_of_four_xx=0
          while read -r response_content_4xx; do
            echo "Processing 4xx metrics for AppDynamics"
            identifier=$(echo "${response_content_4xx}" | awk '{print $1}')
            name_path="${generic_metric_path}|${identifier}"
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            four_xx_count=$(echo "${response_content_4xx}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            echo "$name_path|4XX Count, value=${four_xx_count}"
            #Calaculate Sum of all 5XX errors
            sum_of_four_xx=$((${sum_of_four_xx} + ${four_xx_count}))
          done <jq_processed_4xx_response.out
          echo "$generic_metric_path|4XX Sum, value=${sum_of_four_xx}"
        fi

        #Processing 5xx metrics for AppDynamics
        if [ "${found_5xx}" = "true" ]; then
          sum_of_five_xx=0
          while read -r response_content_5xx; do
            echo "Processing 5xx metrics for AppDynamics"
            identifier=$(echo "${response_content_5xx}" | awk '{print $1}')
            name_path="${generic_metric_path}|${identifier}"
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            five_xx_count=$(echo "${response_content_5xx}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')

            echo "$name_path|5XX Count, value=${five_xx_count}"
            #Calaculate Sum of all 5XX errors
            sum_of_five_xx=$((${sum_of_five_xx} + ${five_xx_count}))
          done <jq_processed_5xx_response.out
          echo "$generic_metric_path|5XX Sum, value=${sum_of_five_xx}"
        fi

        #2.Processing HTTP Status Code Response Codes
        #clean up, but leave response.json to help troubleshoot any issues with this script and/or Apigee's response

        rm jq_processed_*.out metrified_response.out 

        #Send anaytics events
        if (${enable_biq} -eq "true"); then
          echo "BiQ is enabled, sending analytics events "
          source ./analytics/analytics_events.sh
        fi
      fi # end check if identifier string is present in the output

    fi # end 200 response loop
  
  fi   #end if host_url not null

done #end config.json loop
