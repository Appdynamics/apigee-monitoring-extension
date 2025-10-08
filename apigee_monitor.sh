#!/bin/sh

#Author : Israel.Ogbole@appdynamics.com & Stuart.Greenshields@appdynamics.com
version="[ApigeeMonitore v22.1.12  Build Date 2022-01-12]"

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
# Also for onprem APIGEE the Machine Agent needs to be runnning on a server that  is in the same timezone as the APIGEE OnPrem Server server. If it is on prem the config.json, the 
# 'apigee_timezone' param value needs to be set as 'onprem' so that the time query to the APIGEE API is local time. All APIGEE SaaS environment runn as UTC time, so if you are monitoring
# a Saas instance then set the 'apigee_timezone' param value needs to be set as 'saas' which then switches the API query datetime to UTC time. 

# APIGEE ANALYTICS  - IMPORTANT NOTE: 
# Data delay interval. After API calls are made to proxies, APIGEE state it may take upto 10 minutes for the data to appear in their Analytic Management 
# API calls. So although Apigee offer capability of retrieve their analytics for an App/API, they admit that there is a interval of analytics retrieval of +/- 12 minutes. 
# See APIGEE links below:
# Ref:- https://docs.apigee.com/api-platform/analytics/using-analytics-dashboards#whatsthedelayintervalforreceivingdata and
# Ref:- https://community.apigee.com/questions/40479/data-delay-interval-retrieve-time-of-last-update.html
# If there is no data due to their delay in generating their analytic metric data as described above, then the following 'config.json' param of "apigee_query_delay_secs": 120, can be increased to set 
# back further in time to collect. So for example setting this as 300 means the API time query will be run set to start from 5 mins ago from the time of running, or say 600 for the API 
# time query set to start from 10 mins ago from the time of execution (rather than real time or very near time)  


#This will create metrics in specific Tier/Component. Make sure to replace <tier_id> with the appropriate one from your environment.
#To find the tier_id or tier_name in your environment, please follow the screenshot https://docs.appdynamics.com/display/PRO42/Build+a+Monitoring+Extension+Using+Java?preview=/34272441/34413993/componentid.png
#metric_prefix="Server|Component:<tier-name>|Custom Metrics|Apigee"
#This will create metrics in all tiers of your business application
#metric_prefix="Custom Metrics|Apigee"  #Read this value is now from config.json
metric_base="Proxies"
proxy_conf_file_path="apiproxy.conf"
apigee_conf_file="config.json"
log_path="../../logs/apigee-monitor.log"
timer_file="apigee_timer.db"

real_time=true
timeUnit="minute" #A value of second, minute, hour, day, week, month, quarter, year, decade, century, millennium.
apiproxy_names=""
#dimensions="apiproxy,response_status_code,target_response_code,api_product,ax_cache_source,client_id,ax_resolved_client_ip,client_id,developer_app,environment,organization,proxy_basepath,proxy_pathsuffix,apiproxy_revision,virtual_host,ax_ua_device_category,ax_ua_os_family,ax_ua_os_version,proxy_client_ip,ax_true_client_ip,client_ip,request_path,request_uri,request_verb,useragent,ax_ua_agent_family,ax_ua_agent_type,ax_ua_agent_version,target_basepath,target_host,target_ip,target_url,x_forwarded_for_ip,ax_day_of_week,ax_month_of_year,ax_hour_of_day,ax_dn_region,ax_dn_region,client_ip"
dimensions="apiproxy"

metric_curl_output="metric_response.json"
fourzeroone_curl_output="401_response.json"
fourzerothree_curl_output="403_response.json"
fivezerotwo_curl_output="502_response.json"
fivezerothree_curl_output="503_response.json"
fivezerofour_curl_output="504_response.json"
fourxx_curl_output="4xx_response.json"
fivexx_curl_output="5xx_response.json"


#analytics output 
biq_perf_metrics="biq_prepped_perf_metrics.json"
biq_401_metrics="biq_prepped_401_metrics.json"
biq_403_metrics="biq_prepped_403_metrics.json"
biq_502_metrics="biq_prepped_502_metrics.json"
biq_503_metrics="biq_prepped_503_metrics.json"
biq_504_metrics="biq_prepped_504_metrics.json"
biq_5xx_metrics="biq_prepped_5xx_metrics.json"
biq_4xx_metrics="biq_prepped_4xx_metrics.json"


#initialize reponse codes
fourzeroone_curl_response_code=""
fourzerothree_curl_response_code=""
fivezerotwo_curl_response_code=""
fivezerothree_curl_response_code=""
fivezerofour_curl_response_code=""
fourxx_curl_response_code=""
fivexx_curl_response_code=""


metric_curl_response_code=""

found_401="false"
found_403="false"
found_502="false"
found_503="false"
found_504="false"
found_4xx="false"
found_5xx="false"

merged_metric_file="merged_metric_file.out"

readonly ERR_DEPS=0

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

# Prints an error message with an 'ERROR' prefix to stderr.
#
# Args:
#   $1 - error message.
error_msg() {
  echo "ERROR: $1" >&2
}

# Prints an error message followed by an exit.
#
# Args:
#   $1 - error message.
#   $2 - exit code to use.
exit_with_error() {
  error_msg "$1"
  exit "$2"
}

# Checks if packages are installed.
CheckDependencies() {
  if ! command -v curl >/dev/null 2>&1; then
    exit_with_error "curl command unavailable" ${ERR_DEPS}
  elif ! command -v "jq" >/dev/null 2>&1; then
    exit_with_error "jq command unavailable" ${ERR_DEPS}
  fi
}

#ORIGINAL
###################################################################

JSONProccessor() {
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

 
JSON_MetricProcessor(){
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
                | .values 
                ) as $min_request_processing_latency
              | (.metric[]
                | select(.name == "max(request_processing_latency)")
                | .values 
                ) as $max_request_processing_latency
              | (.metric[]
                | select(.name == "max(target_response_time)")
                | .values 
                ) as $max_target_response_time
              | (.metric[]
                | select(.name == "min(target_response_time)")
                | .values 
                ) as $min_target_response_time
              | (.metric[]
                | select(.name == "min(total_response_time)")
                | .values 
                ) as $min_total_response_time
              | (.metric[]
                | select(.name == "max(total_response_time)")
                | .values 
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
          ($min_request_processing_latency | min),
          ($max_request_processing_latency | max),
          ($max_target_response_time | max),
          ($min_target_response_time | min),
          ($min_total_response_time | min),
          ($max_total_response_time | max),
          ($sum_policy_error | add),($sum_target_error | add)
        ' <${1} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' > ${2}

}


#######################################################################################################


#Check package dependencies before running the script
CheckDependencies

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

#Checking if any biq files exist 'biq_*.json' files exists and remove them 
biqfile="biq_*.json"
if [ ! -f "${biqfile}" ]; then
  echo "${biqfile} files do not exist. Skipping..." 
else
  msg="${biqfile} exist. These files must be cleaned up and deleted for this extension to re-run."
  rm ${biqfile} 
  echo "${msg}"
  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg} " >>${log_path}
fi

##Checking if any biq_*.json files exists and remove them
#biqfile="*biq_*.json"
#if ls ${biqfile} >/dev/null 2>&1; then
#  # there were files
#  msg="${biqfile} files exist. These files must be cleaned up and deleted for this extension to re-run."
#  rm ${biqfile}
#  echo "${msg}"
#  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg} " >>${log_path}
#else
#  msg="${biqfile} files do not exist. Skipping as no need to cleanup for rerun"
#  echo "${msg}"
#  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg} " >>${log_path}
#fi

#Set Metric Prefix from config
#Set and greb the config settings from the config.json
metric_prefix=$(jq -r '.metric_prefix' <${apigee_conf_file})
query_limit=$(jq -r '.query_limit' <${apigee_conf_file})
query_interval_in_secs=$(jq -r '.query_interval_in_secs' <${apigee_conf_file}) #in seconds. Best to leave this at 1.5 mins for better accuracy based on my test result. There's a slight lag in the way apigee computes 4xx and 5xx errors stats.
apigee_query_delay_secs=$(jq -r '.apigee_query_delay_secs' <${apigee_conf_file})
apigee_from_in_secs=$((${apigee_query_delay_secs}+${query_interval_in_secs}))
timezone=$(jq -r '.apigee_timezone' <${apigee_conf_file})

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

echo "==> Will use the following proxies if 'use_proxy_filter' is set to true in the config.json file :- ${apiproxy_names}"


#Set Metric Prefix from config
echo ""
if [ "${timezone}" = "saas" ]; then
  echo "The APIGEE instance is a SaaS environment and the timezone datestamp for API query should be set to UTC"
#  if [ ! -f "${timer_file}" ]; then
#   #initial install
#   msg=" ${timer_file} does not exist. This is treated as an initial excution of v21.1.0 or higher."
#   echo "${msg}"
#   echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg}" >>${log_path}
#   #Create the timer file.
#   echo $(date -u +%m/%d/%Y+%H:%M --date="${apigee_query_delay_secs} seconds ago")":00" > "${timer_file}"
#   from_range=$(date -u +%m/%d/%Y+%H:%M --date="${apigee_from_in_secs} seconds ago")":00"
#   to_range="$(<$timer_file)"
#   # The query_interval_in_secs in ONLY used to determine how far back to query Apigee during the inital run of v21.1.0 or higher
#   msg="NO TIMER FILE query: from ${from_range} to ${to_range}"
#   echo "${msg}"
#  else
#   #re-run
#   # prev_run_time=$(cat "${timer_file}") #time of previous run
#   from_range="$(<$timer_file)"
#   echo "$from_range"
#   echo $(date -u +%m/%d/%Y+%H:%M --date="${apigee_query_delay_secs} seconds ago")":00" > "${timer_file}"
#   to_range="$(<$timer_file)"
#   msg="TIMER FILE query: from ${from_range} to ${to_range}"
#   echo "${msg}"
#  fi

  ### LINUX TESTING WITHOUT DB TIMER FILE - GNU date for this if you're using Ubuntu, CentOS or Redhat
  from_range=$(date -u +%m/%d/%Y+%H:%M --date="${apigee_from_in_secs} seconds ago")":00"
  to_range=$(date -u +%m/%d/%Y+%H:%M --date="${apigee_query_delay_secs} seconds ago")":00"
  
  ### MAC TESTING WITHOUT DB TIMER FILE - with  "brew install coreutils" and then calling gdate
  #from_range=$(gdate -u +%m/%d/%Y+%H:%M --date="${apigee_from_in_secs} seconds ago")":00"
  #to_range=$(gdate -u +%m/%d/%Y+%H:%M --date="${apigee_query_delay_secs} seconds ago")":00"
  
  msg="TIME RANGE FOR THE TIME APIGEE API COLLECTION RUN IS: from ${from_range} to ${to_range} (UTC Time)"
  echo "${msg}"
  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg}" >>${log_path}
  
elif [ "${timezone}" = "onprem" ]; then
  echo "The APIGEE instance is a ONPREM environment and the timezone datestamp for API query should be set to the 'local' time of the MachineAgent and the APIGEE onprem server (i.e. they must be are in the same timezone)"
#  if [ ! -f "${timer_file}" ]; then
#   #initial install
#   msg=" ${timer_file} does not exist. This is treated as an initial excution of v21.1.0 or higher."
#   echo "${msg}"
#   echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg}" >>${log_path}
#   #Create the timer file.
#   echo $(date +%m/%d/%Y+%H:%M --date="${apigee_query_delay_secs} seconds ago")":00" > "${timer_file}"
#   from_range=$(date +%m/%d/%Y+%H:%M --date="${apigee_from_in_secs} seconds ago")":00"
#   to_range="$(<$timer_file)"
#   # The query_interval_in_secs in ONLY used to determine how far back to query Apigee during the inital run of v21.1.0 or higher
#   msg="NO TIMER FILE query: from ${from_range} to ${to_range}"
#   echo "${msg}"
#  else
#   #re-run
#   # prev_run_time=$(cat "${timer_file}") #time of previous run
#   from_range="$(<$timer_file)"
#   echo "$from_range"
#   echo $(date +%m/%d/%Y+%H:%M --date="${apigee_query_delay_secs} seconds ago")":00" > "${timer_file}"
#   to_range="$(<$timer_file)"
#   msg="TIMER FILE query: from ${from_range} to ${to_range}"
#   echo "${msg}"
#  fi

  ### LINUX TESTING WITHOUT DB TIMER FILE - GNU date for this if you're using Ubuntu, CentOS or Redhat
  from_range=$(date +%m/%d/%Y+%H:%M --date="${apigee_from_in_secs} seconds ago")":00"
  to_range=$(date +%m/%d/%Y+%H:%M --date="${apigee_query_delay_secs} seconds ago")":00"

  ### MAC TESTING WITHOUT DB TIMER FILE - with  "brew install coreutils" and then calling gdate
  #from_range=$(gdate +%m/%d/%Y+%H:%M --date="${apigee_from_in_secs} seconds ago")":00"
  #to_range=$(gdate +%m/%d/%Y+%H:%M --date="${apigee_query_delay_secs} seconds ago")":00"
  
  msg="TIME RANGE FOR THE TIME APIGEE API COLLECTION RUN IS SET TO THE LOCAL SERVER  TIME ON WHICH IT RUNS: from ${from_range} to ${to_range}"
  echo "${msg}"
  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] ${msg}" >>${log_path}
  
else
  msg="'apigee_timezone' in the config.json is not set to either 'saas' or onprem'. It is set to '${timezone}'. This config.json param is required for this extension to work. If your APIGEE environment is an 'onprem' environment then the Machine agent should be located in the same local timezone as your APIGEE onprem server and there the timezone will be local, Therfore the 'apigee_timezone' field in the config.json should be set to 'onprem' for this. If your apigee nevironment is saas, this environment always runs UTC time, then set the 'apigee_timezone' field in the config.json to 'saas'"
  echo "${msg}"
  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg} " >>${log_path}
  exit 1
fi

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
  _arg_use_encoded_credentials=$(_ijq '.is_password_encoded')

  if [ -n "${host_name}" ] && [ -n "${environments}" ] && [ -n "${organization}" ]; then
 
    # decode passwords if encoded
    if [ "${_arg_use_encoded_credentials}" = "true" ]; then
        echo "Password is ENCODED"
        _arg_password=$(_ijq '.password')
        password=$(eval echo ${_arg_password} | base64 --decode)
    elif [ "${_arg_use_encoded_credentials}" = "false" ]; then
        echo "Password is NOT ENCODED"
        password=$(_ijq '.password')
    fi
    
    # build user credentials
    username=$(_ijq '.username')
    server_friendly_name=$(_ijq '.server_friendly_name')
    use_proxy_filter=$(_ijq '.use_proxy_filter')

    if [ -z "${server_friendly_name}" ]; then
      server_friendly_name=$(echo "${host_name}" | sed 's~http[s]*://~~g')
    fi

    echo "===> Processing host_name:${host_name} ~~ env:${environments}  ~~ org:${organization} ~  \
      server_friendly_name : ${server_friendly_name} ~ use_proxy_filter : $use_proxy_filter ~ username : ${username}  ~ password : ****** "

    base_url="${host_name}/v1/organizations"
    
    
    #fourxx="&filter=((response_status_code%20ge%20404%20and%20response_status_code%20le%20499)%20or%20response_status_code%20eq%20402)"
    fourxx="&filter=((response_status_code%20ge%20400%20and%20response_status_code%20le%20499)%20and%20response_status_code%20notin%20401%2C403)"
    #fivexx="&filter=((response_status_code%20ge%20505%20and%20response_status_code%20le%20599)%20or%20(response_status_code%20ge%20500%20and%20response_status_code%20le%20501))"
    fivexx="&filter=(response_status_code%20ge%20500%20and%20response_status_code%20notin%20502%2C503%2C504)"
    fourzeroone="&filter=(response_status_code%20eq%20401)"
    fourzerothree="&filter=(response_status_code%20eq%20403)"
    fivezerotwo="&filter=(response_status_code%20eq%20502)"
    fivezerothree="&filter=(response_status_code%20eq%20503)"
    fivezerofour="&filter=(response_status_code%20eq%20504)"
    
    #fourxx_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20(response_status_code%20ge%20404%20and%20response_status_code%20le%20499)%20or%20response_status_code%20eq%20402)"
    fourxx_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20(response_status_code%20ge%20400%20and%20response_status_code%20le%20499)%20and%20response_status_code%20notin%20401%2C403)"
    #fivexx_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20(response_status_code%20ge%20505%20and%20response_status_code%20le%20599)%20or%20(response_status_code%20ge%20500%20and%20response_status_code%20le%20501))"
    fivexx_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20response_status_code%20ge%20500%20and%20response_status_code%20notin%20502%2C503%2C504)"
    fourzeroone_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20response_status_code%20eq%20401)"
    fourzerothree_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20response_status_code%20eq%20403)"
    fivezerotwo_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20response_status_code%20eq%20502)"
    fivezerothree_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20response_status_code%20eq%20503)"
    fivezerofour_proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names}%20and%20response_status_code%20eq%20504)"
    proxy_filter="&filter=(apiproxy%20in%20${apiproxy_names})"

    min_max_params=",max(total_response_time),min(total_response_time),max(target_response_time),min(target_response_time),min(request_processing_latency),max(request_processing_latency)"
    query_params="&select=sum(message_count),avg(total_response_time),avg(target_response_time),avg(request_processing_latency),sum(is_error),sum(target_error),sum(policy_error)"

    req="${base_url}/${organization}/environments/${environments}/stats/${dimensions}?_optimized=js&realtime=${real_time}&limit=${query_limit}${query_params}${min_max_params}&sort=DESC&sortby=sum(message_count),avg(total_response_time),sum(is_error)&timeRange=${from_range}~${to_range}&timeUnit=${timeUnit}&tsAscending=true"

    #use ${filtered_req} if you want to use the filtered request and ${req} for unfiltered
    if [ "${use_proxy_filter}" = "true" ]; then
      echo "Using filtered request"
      echo "Metric request.."
      IOcURL "${req}${proxy_filter}" "${username}" "${password}" ${metric_curl_output}
      metric_curl_response_code=${response}
      echo "metric_curl_response_code==>$metric_curl_response_code"
  
      echo "401 request..."
      IOcURL "${req}${fourzeroone_proxy_filter}" "${username}" "${password}" ${fourzeroone_curl_output}
      fourzeroone_curl_response_code=${response}
      echo "fourzeroone_curl_response_code==> ${fourzeroone_curl_response_code}"

      echo "403 request..."
      IOcURL "${req}${fourzerothree_proxy_filter}" "${username}" "${password}" ${fourzerothree_curl_output}
      fourzerothree_curl_response_code=${response}
      echo "fourzerothree_curl_response_code==> ${fourzerothree_curl_response_code}"

      echo "4xx request..."
      IOcURL "${req}${fourxx_proxy_filter}" "${username}" "${password}" ${fourxx_curl_output}
      fourxx_curl_response_code=${response}
      echo "fourxx_curl_response_code==> ${fourxx_curl_response_code}"

      echo "502 request..."
      IOcURL "${req}${fivezerotwo_proxy_filter}" "${username}" "${password}" ${fivezerotwo_curl_output}
      fivezerotwo_curl_response_code=${response}
      echo "fivezerotwo_curl_response_code==> ${fivezerotwo_curl_response_code}"

      echo "503 request..."
      IOcURL "${req}${fivezerothree_proxy_filter}" "${username}" "${password}" ${fivezerothree_curl_output}
      fivezerothree_curl_response_code=${response}
      echo "fivezerothree_curl_response_code==> ${fivezerothree_curl_response_code}"

      echo "504 request..."
      IOcURL "${req}${fivezerofour_proxy_filter}" "${username}" "${password}" ${fivezerofour_curl_output}
      fivezerofour_curl_response_code=${response}
      echo "fivezerofour_curl_response_code==> ${fivezerofour_curl_response_code}"

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

      echo "401 request..."
      IOcURL "${req}${fourzeroone}" "${username}" "${password}" ${fourzeroone_curl_output}
      fourzeroone_curl_response_code=${response}
      echo "fourzeroone_curl_response_code==> ${fourzeroone_curl_response_code}"

      echo "403 request..."
      IOcURL "${req}${fourzerothree}" "${username}" "${password}" ${fourzerothree_curl_output}
      fourzerothree_curl_response_code=${response}
      echo "fourzerothree_curl_response_code==> ${fourzerothree_curl_response_code}"

      echo "4xx  request..."
      IOcURL "${req}${fourxx}" "${username}" "${password}" ${fourxx_curl_output}
      fourxx_curl_response_code=${response}
      echo "fourxx_curl_response_code==> ${fourxx_curl_response_code}"

      echo "502 request..."
      IOcURL "${req}${fivezerotwo}" "${username}" "${password}" ${fivezerotwo_curl_output}
      fivezerotwo_curl_response_code=${response}
      echo "fivezerotwo_curl_response_code==> ${fivezerotwo_curl_response_code}"

      echo "503 request..."
      IOcURL "${req}${fivezerothree}" "${username}" "${password}" ${fivezerothree_curl_output}
      fivezerothree_curl_response_code=${response}
      echo "fivezerothree_curl_response_code==> ${fivezerothree_curl_response_code}"

      echo "504 request..."
      IOcURL "${req}${fivezerofour}" "${username}" "${password}" ${fivezerofour_curl_output}
      fivezerofour_curl_response_code=${response}
      echo "fivezerofour_curl_response_code==> ${fivezerofour_curl_response_code}"

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
        JSON_MetricProcessor ${metric_curl_output} jq_processed_response.out
        
        #1.Processing Performance metrics outputs.
        #tranpose the matrix of the metrics
        #a=identifier
        #b=global-avg-total_response_time
        #c=global-avg-request_processing_latency
        #d=global-avg-request_processing_latency
        #e=message_count
        #f=error_count
        #g=avg_total_response_time
        #h=avg_target_response_time
        #i=avg_request_processing_latency

        #additional metrics - 25/03/2020 
        #j=min_request_processing_latency
        #k=max_request_processing_latency

        #l=max_target_response_time
        #m=min_target_response_time

         #n=min_total_response_time
         #o=max_total_response_time

         #p=sum_policy_error
         #q=sum_target_error

        awk 'NF>0{a=$0;getline b; getline c; getline d; getline e; getline f; getline g; getline h; getline i; getline j; getline k; getline l; getline m; getline n; getline o; getline p; getline q;
                  print a FS b FS c FS d FS e FS f FS g FS h FS i FS j FS k FS l FS m FS n FS o FS p FS q}' jq_processed_response.out >metrified_response.out

        #Process BiQ Data 
        JSONProccessor ${metric_curl_output} raw_${biq_perf_metrics}
        #Add Apigee Environment details to help distinguish data source in BiQ
        jq  --arg name "${server_friendly_name}" --arg env "${environments}"  --arg org "${organization}"  '.[]  += {"server_friendly_name":$name, "environment":$env, "organization":$org}' < raw_${biq_perf_metrics} > ${biq_perf_metrics}
      
        echo "DEBUG: Processing API Proxy ${fourzeroone_curl_output} collections"                 
        finder_401="identifier"
        if ! grep -q ${finder_401} "${fourzeroone_curl_output}"; then
          msg="The 401 request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
                this usually mean no proxy returned 401 response code from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
          echo " 401 does not exist. setting metrified_response.out as the final output"
          # merged_metric_file="metrified_response.out"
        else
          jq -r '
                    .[].stats.data[]
                    | (.identifier.values[0]) as $identifier
                    | (.metric[]
                          | select(.name == "sum(message_count)")
                          | .values
                          ) as $fourzeroone_count
                    | [$identifier | gsub("( ? )"; ""), ($fourzeroone_count | add)] | @tsv
                  ' <${fourzeroone_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_401_response.out
          found_401="true"
          #401 BiQ Processor
          JSONProccessor ${fourzeroone_curl_output} biq_401_raw.json
          cat biq_401_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, error_401: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_401_metrics}
        fi

        echo "DEBUG: Processing API Proxy ${fourzerothree_curl_output} collections"
        finder_403="identifier"
        if ! grep -q ${finder_403} "${fourzerothree_curl_output}"; then
          msg="The 403 request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
                this usually mean no proxy returned 403 response code from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
          echo " 403 does not exist. setting metrified_response.out as the final output"
          # merged_metric_file="metrified_response.out"
        else
          jq -r '
                    .[].stats.data[]
                    | (.identifier.values[0]) as $identifier
                    | (.metric[]
                          | select(.name == "sum(message_count)")
                          | .values
                          ) as $fourzerothree_count
                    | [$identifier | gsub("( ? )"; ""), ($fourzerothree_count | add)] | @tsv
                  ' <${fourzerothree_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_403_response.out

          found_403="true"

          #403 BiQ Processor
          JSONProccessor ${fourzerothree_curl_output} biq_403_raw.json
          cat biq_403_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, error_403: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_403_metrics}   
        fi

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
          cat biq_4xx_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, error_4xx: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_4xx_metrics}
         
        fi

        echo "DEBUG: Processing API Proxy ${fivezerotwo_curl_output} collections"
        finder_502="identifier"
        if ! grep -q ${finder_502} "${fivezerotwo_curl_output}"; then
          msg="The 502 request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
                this usually mean no proxy returned 502 response code from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
          echo " 502 does not exist. setting metrified_response.out as the final output"
          # merged_metric_file="metrified_response.out"
        else
          jq -r '
                    .[].stats.data[]
                    | (.identifier.values[0]) as $identifier
                    | (.metric[]
                          | select(.name == "sum(message_count)")
                          | .values
                          ) as $fivezerotwo_count
                    | [$identifier | gsub("( ? )"; ""), ($fivezerotwo_count | add)] | @tsv
                  ' <${fivezerotwo_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_502_response.out

          found_502="true"

          #502 BiQ Processor
          JSONProccessor ${fivezerotwo_curl_output} biq_502_raw.json
          cat biq_502_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, error_502: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_502_metrics}
        fi

        echo "DEBUG: Processing API Proxy ${fivezerotwo_curl_output} collections"                 
        finder_502="identifier"
        if ! grep -q ${finder_502} "${fivezerotwo_curl_output}"; then
          msg="The 502 request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
                this usually mean no proxy returned 502 response code from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
          echo " 502 does not exist. setting metrified_response.out as the final output"
          # merged_metric_file="metrified_response.out"
        else
          jq -r '
                    .[].stats.data[]
                    | (.identifier.values[0]) as $identifier
                    | (.metric[]
                          | select(.name == "sum(message_count)")
                          | .values
                          ) as $fivezerotwo_count
                    | [$identifier | gsub("( ? )"; ""), ($fivezerotwo_count | add)] | @tsv
                  ' <${fivezerotwo_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_502_response.out
          found_502="true"
          #504 BiQ Processor
          JSONProccessor ${fivezerotwo_curl_output} biq_502_raw.json
          cat biq_502_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, error_502: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_50_metrics}
        fi

        echo "DEBUG: Processing API Proxy ${fivezerothree_curl_output} collections"
        finder_503="identifier"
        if ! grep -q ${finder_503} "${fivezerothree_curl_output}"; then
          msg="The 503 request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
                this usually mean no proxy returned 503 response code from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
          echo " 503 does not exist. setting metrified_response.out as the final output"
          # merged_metric_file="metrified_response.out"
        else
          jq -r '
                    .[].stats.data[]
                    | (.identifier.values[0]) as $identifier
                    | (.metric[]
                          | select(.name == "sum(message_count)")
                          | .values
                          ) as $fivezerothree_count
                    | [$identifier | gsub("( ? )"; ""), ($fivezerothree_count | add)] | @tsv
                  ' <${fivezerothree_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_503_response.out

          found_503="true"

          #503 BiQ Processor
          JSONProccessor ${fivezerothree_curl_output} biq_503_raw.json
          cat biq_503_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, error_503: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_503_metrics}
        fi

        echo "DEBUG: Processing API Proxy ${fivezerofour_curl_output} collections"                 
        finder_504="identifier"
        if ! grep -q ${finder_504} "${fivezerofour_curl_output}"; then
          msg="The 504 request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
                this usually mean no proxy returned 504 response code from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
          echo " 504 does not exist. setting metrified_response.out as the final output"
          # merged_metric_file="metrified_response.out"
        else
          jq -r '
                    .[].stats.data[]
                    | (.identifier.values[0]) as $identifier
                    | (.metric[]
                          | select(.name == "sum(message_count)")
                          | .values
                          ) as $fivezerofour_count
                    | [$identifier | gsub("( ? )"; ""), ($fivezerofour_count | add)] | @tsv
                  ' <${fivezerofour_curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' >jq_processed_504_response.out
          found_504="true"
          #504 BiQ Processor
          JSONProccessor ${fivezerofour_curl_output} biq_504_raw.json
          cat biq_504_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, error_504: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_504_metrics}
        fi



        echo "DEBUG: Processing ${fivexx_curl_output} collections"
        finder_5xx="identifier"
        if ! grep -q ${finder_5xx} "${fivexx_curl_output}"; then
          msg="The 5xx request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
                this usually mean no proxy returned 5xx response code from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >>${log_path}
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
          cat  biq_5xx_raw.json | jq -r '.[]  | {apiproxy: .apiproxy, error_5xx: ."sum(message_count)"}' |  awk '/}/{print $0 ","; next}1' |  sed '$ s/.$//' | awk 'BEGINFILE{print "["};ENDFILE{print "]"};1' > ${biq_5xx_metrics}

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
          #additional metrics - 25/03/2020 
          min_request_processing_latency=$(echo "${response_content}" | awk '{print $10}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          max_request_processing_latency=$(echo "${response_content}" | awk '{print $11}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')

          max_target_response_time=$(echo "${response_content}" | awk '{print $12}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          min_target_response_time=$(echo "${response_content}" | awk '{print $13}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
        
          min_total_response_time=$(echo "${response_content}" | awk '{print $14}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          max_total_response_time=$(echo "${response_content}" | awk '{print $15}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          
          sum_policy_error=$(echo "${response_content}" | awk '{print $16}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
          sum_target_error=$(echo "${response_content}" | awk '{print $17}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')

          #parameterising the paths to make it easier to manager in the future
          name_path="${generic_metric_path}|${identifier}"
          echo "$name_path|Availability, value=1"
          echo "$name_path|Total Message Count, value=${message_count}"
          echo "$name_path|Total Error Count, value=${error_count}"
          echo "$name_path|Total Policy Errors, value=${sum_policy_error}"
          echo "$name_path|Total Target Errors, value=${sum_target_error}"

          echo "$name_path|Global Average Response Time, value=${global_avg_total_response_time}"
          echo "$name_path|Average Total Response Time, value=${avg_total_response_time}"
          echo "$name_path|Minimum Total Response Time, value=${min_total_response_time}"
          echo "$name_path|Maximum Total Response Time, value=${max_total_response_time}"
     
          echo "$name_path|Global Request Processing Latency, value=${global_avg_request_processing_latency}"
          echo "$name_path|Average Request Processing Latency, value=${avg_request_processing_latency}"
          echo "$name_path|Minimum Request Processing Latency, value=${min_request_processing_latency}"
          echo "$name_path|Maximum Request Processing Latency, value=${max_request_processing_latency}"
          
          echo "$name_path|Global Average Target Response Time, value=${global_avg_target_response_time}"
          echo "$name_path|Average Target Response Time, value=${avg_target_response_time}"
          echo "$name_path|Minimum Target Response Time, value=${min_target_response_time}"
          echo "$name_path|Maximum Target Response Time, value=${max_target_response_time}"
         
          sum_of_messages=$(($sum_of_messages + $message_count))
          sum_of_errors=$(($sum_of_errors + ${error_count}))
          overrall_response_time=$(($overrall_response_time + $avg_total_response_time))
          i=$(($i + 1))
        done <metrified_response.out

        avg=$(($overrall_response_time / $i))
        rounded_avg=$(echo ${avg} | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
        echo "$generic_metric_path|Average Response Time, value=${rounded_avg}"
        echo "$generic_metric_path|Total Message Count, value=${sum_of_messages}"
        echo "$generic_metric_path|Total Error Count, value=${sum_of_errors}"

        #Processing 401 metrics for AppDynamics
        if [ "${found_401}" = "true" ]; then
          sum_of_four_zero_one=0
          while read -r response_content_401; do
            echo "Processing APIPROXY 401 metrics for AppDynamics"
            identifier=$(echo "${response_content_401}" | awk '{print $1}')
            name_path="${generic_metric_path}|${identifier}"
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            four_zero_one_count=$(echo "${response_content_401}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            echo "$name_path|401 Count, value=${four_zero_one_count}"
            #Calculate Sum of all 401 errors
            sum_of_four_zero_one=$((${sum_of_four_zero_one} + ${four_zero_one_count}))
          done <jq_processed_401_response.out
          echo "$generic_metric_path|Total 401, value=${sum_of_four_zero_one}"
        fi

        #Processing 403 metrics for AppDynamics
        if [ "${found_403}" = "true" ]; then
          sum_of_four_zero_three=0
          while read -r response_content_403; do
            echo "Processing APIPROXY 403 metrics for AppDynamics"
            identifier=$(echo "${response_content_403}" | awk '{print $1}')
            name_path="${generic_metric_path}|${identifier}"
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            four_zero_three_count=$(echo "${response_content_403}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            echo "$name_path|403 Count, value=${four_zero_three_count}"
            #Calculate Sum of all 403 errors
            sum_of_four_zero_three=$((${sum_of_four_zero_three} + ${four_zero_three_count}))
          done <jq_processed_403_response.out
          echo "$generic_metric_path|Total 403, value=${sum_of_four_zero_three}"
        fi

        #Processing 4xx metrics for AppDynamics
        if [ "${found_4xx}" = "true" ]; then
          sum_of_four_xx=0
          while read -r response_content_4xx; do
            echo "Processing APIPROXY Other 4xx metrics for AppDynamics"
            identifier=$(echo "${response_content_4xx}" | awk '{print $1}')
            name_path="${generic_metric_path}|${identifier}"
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            four_xx_count=$(echo "${response_content_4xx}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            echo "$name_path|4XX Count, value=${four_xx_count}"
            #Calaculate Sum of all 5XX errors
            sum_of_four_xx=$((${sum_of_four_xx} + ${four_xx_count}))
          done <jq_processed_4xx_response.out
          echo "$generic_metric_path|Total 4XX, value=${sum_of_four_xx}"
        fi

        #Processing 502 metrics for AppDynamics
        if [ "${found_502}" = "true" ]; then
          sum_of_five_zero_two=0
          while read -r response_content_502; do
            echo "Processing APIPROXY 502 metrics for AppDynamics"
            identifier=$(echo "${response_content_502}" | awk '{print $1}')
            name_path="${generic_metric_path}|${identifier}"
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            five_zero_two_count=$(echo "${response_content_502}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')

            echo "$name_path|502 Count, value=${five_zero_two_count}"
            #Calaculate Sum of all 502 errors
            sum_of_five_zero_two=$((${sum_of_five_zero_two} + ${five_zero_two_count}))
          done <jq_processed_502_response.out
          echo "$generic_metric_path|Total 502, value=${sum_of_five_zero_two}"
        fi

        #Processing 503 metrics for AppDynamics
        if [ "${found_503}" = "true" ]; then
          sum_of_five_zero_three=0
          while read -r response_content_503; do
            echo "Processing APIPROXY 503 metrics for AppDynamics"
            identifier=$(echo "${response_content_503}" | awk '{print $1}')
            name_path="${generic_metric_path}|${identifier}"
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            five_zero_three_count=$(echo "${response_content_503}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')

            echo "$name_path|503 Count, value=${five_zero_three_count}"
            #Calaculate Sum of all 503 errors
            sum_of_five_zero_three=$((${sum_of_five_zero_three} + ${five_zero_three_count}))
          done <jq_processed_503_response.out
          echo "$generic_metric_path|Total 503, value=${sum_of_five_zero_three}"
        fi

        #Processing 504 metrics for AppDynamics
        if [ "${found_504}" = "true" ]; then
          sum_of_five_zero_four=0
          while read -r response_content_504; do
            echo "Processing APIPROXY 504 metrics for AppDynamics"
            identifier=$(echo "${response_content_504}" | awk '{print $1}')
            name_path="${generic_metric_path}|${identifier}"
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            five_zero_four_count=$(echo "${response_content_504}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')

            echo "$name_path|504 Count, value=${five_zero_four_count}"
            #Calaculate Sum of all 504 errors
            sum_of_five_zero_four=$((${sum_of_five_zero_four} + ${five_zero_four_count}))
          done <jq_processed_504_response.out
          echo "$generic_metric_path|Total 504, value=${sum_of_five_zero_four}"
        fi


        #Processing 5xx metrics for AppDynamics
        if [ "${found_5xx}" = "true" ]; then
          sum_of_five_xx=0
          while read -r response_content_5xx; do
            echo "Processing APIPROXY Other 5xx metrics for AppDynamics"
            identifier=$(echo "${response_content_5xx}" | awk '{print $1}')
            name_path="${generic_metric_path}|${identifier}"
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            five_xx_count=$(echo "${response_content_5xx}" | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')

            echo "$name_path|5XX Count, value=${five_xx_count}"
            #Calaculate Sum of all 5XX errors
            sum_of_five_xx=$((${sum_of_five_xx} + ${five_xx_count}))
          done <jq_processed_5xx_response.out
          echo "$generic_metric_path|Total 5XX, value=${sum_of_five_xx}"
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
