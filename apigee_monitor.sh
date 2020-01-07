#!/bin/sh

#Author : Israel.Ogbole@appdynamics.com
version="[ApigeeMonitore v2.5.0 Build Date 2020-01-08 12:59]"

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
metric_prefix="Custom Metrics|Apigee"
metric_base="Proxies"
proxy_conf_file_path="apiproxy.conf"
apigee_conf_file="config.json"
log_path="../../logs/apigee-monitor.log"

real_time=true
query_interval=2 #in minutues. This value must be the same as the execution frequency value set in the monitor.xml file
query_limit=120
timeUnit="minute" #A value of second, minute, hour, day, week, month, quarter, year, decade, century, millennium.
apiproxy_names=""

#takes 3 params in this order 1. requst url 2. username 3. password
IOcURL() {
 #clean up any orphaned file from the previous run. 
 #rm jq_processed_response.out metrified_response.out jq_processed_status_code.out

  [ -z "${curl_output}" ] && curl_output="response.json"
  [ -f "${curl_output}" ] && rm ${curl_output}
  
  echo "curl ${1} -u ${2}:******"

  # for added security, store your password in a file, and cat it like this $(cat .password), otherwise password will be visible in bash history
  # or use -n (.netrc) instead
  #curl_response_code=$(curl -u ${apigee_username}:${apigee_password} -s -w "%{http_code}" -o "${curl_output}" -X GET "${1}")
  curl_response_code=$(curl -u ${2}:${3} -s -w "%{http_code}" -o "${curl_output}" -X GET "${1}")
  
  echo "==> ${curl_response_code}"
}

#Initialise log with version
echo "{$version}" >> ${log_path}

if [ ! -f "${proxy_conf_file_path}" ]; then
    msg="${proxy_conf_file_path} does not exist. \n This file is required for this extension to work.\
    Create a line delimited list of your api proxy names i.e one proxy per line and ensure you hit enter"
    echo ${msg}
    echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >> ${log_path}
    exit 1
fi

if [ ! -f "${apigee_conf_file}" ]; then
    msg="${apigee_conf_file} does not exist. This file is required for this extension to work."
    echo ${msg}
    echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >> ${log_path}
    exit 1
fi

#read proxy names from the conf file
while read -r proxy_name ; do
	#concatenate  proxy_names - seperated by commas and put them in between single qoutes ''
	apiproxy_names="${apiproxy_names}'${proxy_name}',"
done < "${proxy_conf_file_path}"

#remove the last comma in the line with sed                      and the last whitespace
apiproxy_names=$(echo ${apiproxy_names} | sed 's/\(.*\),/\1 /' | awk '{$1=$1}1')

echo "==> Will use the following proxies if 'use_proxy_filter' is set to true in the config.json file : ${apiproxy_names}"

#Use this if you're using Mac OS
#minutes_ago=$(date -r $(( $(date +%s) - 600 )) | awk '{print $4}')
#time_now=$(date +"%T")
#today=$(date +"%m/%d/%Y")
#to_range=$(echo ${today}+${time_now})
#from_range=$(echo ${today}+${minutes_ago})

#or this if you're using Ubuntu, CentOS or Redhat 
to_range=$(date +%m/%d/%Y+%H:%M:%S)
from_range=$(date +%m/%d/%Y+%H:%M:%S --date="$query_interval minutes ago")

echo "==> Time range: from ${from_range} to ${to_range}"

# Read BiQ flag from config file 
enable_biq=$(jq -r  '.enable_BiQ' < ${apigee_conf_file})

echo "==>Enable BiQ for error code = ${enable_biq}"

for row in $(cat ${apigee_conf_file} | jq -r ' .connection_details[] | @base64'); do
     _ijq() {
      echo ${row} | base64 --decode | jq -r ${1}
      }
     
  if [ ! -z $(_ijq '.host_url') ] && [ ! -z $(_ijq '.env') ] && [ ! -z $(_ijq '.org') ] ; then 
      host_name=$(_ijq '.host_url')
      environments=$(_ijq '.env')   
      organization=$(_ijq '.org') 
      username=$(_ijq '.username') 
      password=$(_ijq '.password')
      server_friendly_name=$(_ijq '.server_friendly_name')
      use_proxy_filter=$(_ijq '.use_proxy_filter')

      if [ -z "${server_friendly_name}" ]; then 
        server_friendly_name=$(echo ${host_name} | sed 's~http[s]*://~~g')
      fi 

      echo "===> Processing host_name:${host_name} ~~ env:${environments}  ~~ org:${organization} ~  \
      server_friendly_name : ${server_friendly_name} ~ use_proxy_filter : $use_proxy_filter ~ username : ${username}  ~ password : ****** "

      base_url="${host_name}/v1/organizations"

      req="${base_url}/${organization}/environments/${environments}/stats/apiproxy,response_status_code,target_response_code?_optimized=js&realtime=${real_time}&limit=${query_limit}&select=sum(message_count),avg(total_response_time),avg(target_response_time),avg(request_processing_latency),sum(is_error)&sort=DESC&sortby=sum(message_count),avg(total_response_time),sum(is_error)&timeRange=${from_range}~${to_range}&timeUnit=${timeUnit}&tsAscending=true"
      
      filtered_req="${base_url}/${organization}/environments/${environments}/stats/apiproxy,response_status_code,target_response_code?_optimized=js&realtime=${real_time}&filter=(apiproxy%20in%20${apiproxy_names})&limit=${query_limit}&select=sum(message_count),avg(total_response_time),avg(target_response_time),avg(request_processing_latency),sum(is_error)&sort=DESC&sortby=sum(message_count),avg(total_response_time),sum(is_error)&timeRange=${from_range}~${to_range}&timeUnit=${timeUnit}&tsAscending=true"

      #https://api.enterprise.apigee.com/v1/organizations/iogbole-70230-eval/environments/prod/stats/apiproxy,response_status_code,target_response_code?_optimized=js&select=sum(message_count),sum(is_error),avg(total_response_time),avg(target_response_time)&sort=DESC&sortby=sum(message_count),sum(is_error),avg(total_response_time),avg(target_response_time)&timeRange=12/18/2019+00:00:15~12/19/2019+00:50:15"
        #send the request to Apigee
        #use ${filtered_req} if you want to use the filtered request and ${req} for unfiltered
        echo "sending request to Apigee.... " 

      if [ "${use_proxy_filter}" = "true" ]; then
          echo "Using filtered request"
          IOcURL "${filtered_req}" "${username}" "${password}"   
        else
          echo "Using un-filtered request - collecting all proxy information"
          IOcURL "${req}" "${username}" "${password}"   
      fi

        if [ "${curl_response_code}" -ne 200 ]; then
            msg="The request failed with ${curl_response_code} response code.\n \
              The requested URL is: ${req} \n \
              Apigee's Response is :\n   $(cat ${curl_output}) \n"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >> ${log_path}
          exit 1
        fi

        if [ ! -f "${curl_output}" ]; then
          msg="The output of the cURL request wasn't saved. Please ensure that $(whoami) user has write acccess to $(pwd). Exiting..."
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >> ${log_path}
          exit 0
        fi

        #check if identifier string is present in the output
        if ! grep -q identifier "${curl_output}"; then
          msg="The request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
          Please make sure there is traffic - from ${from_range} to ${to_range}"
          echo "${msg}"
          echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INFO] $msg" >> ${log_path}
          exit 0
        fi

        #now it's time for the fun bit that I always dread:)
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
            | $identifier, $global_avg_total_response_time, $global_avg_request_processing_latency,$global_avg_target_response_time,
            ($message_count | add),($error_count | add),($avg_total_response_time | add)/ ($avg_total_response_time | length),
            ($avg_target_response_time | add)/ ($avg_target_response_time | length),
            ($avg_request_processing_latency | add)/ ($avg_request_processing_latency | length)
          '< ${curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' > jq_processed_response.out

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
              print a FS b FS c FS d FS e FS f FS g FS h FS i}' jq_processed_response.out > metrified_response.out

        while read -r response_content ; do
            identifier=$(echo ${response_content} | awk '{print $1}')
            #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
            global_avg_total_response_time=$(echo ${response_content}  | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            global_avg_request_processing_latency=$(echo ${response_content}  | awk '{print $3}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            global_avg_target_response_time=$(echo ${response_content}  | awk '{print $4}' |awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            #additional metrics - 19/12/2019 
            message_count=$(echo ${response_content}  | awk '{print $5}' |awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            error_count=$(echo ${response_content}  | awk '{print $6}' |awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            avg_total_response_time=$(echo ${response_content}  | awk '{print $7}' |awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            avg_target_response_time=$(echo ${response_content}  | awk '{print $8}' |awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            avg_request_processing_latency=$(echo ${response_content}  | awk '{print $9}' |awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
            
            #parameterising the paths to make it easier to manager in the future
            name_path="name=${metric_prefix}|${server_friendly_name}|${metric_base}|${environments}|${identifier}"
            
            echo "$name_path|Availability, value=1"
            echo "$name_path|Total Message Count, value=${message_count}"
            echo "$name_path|Total Error Count, value=${error_count}"
            echo "$name_path|Global Average Response Time, value=${global_avg_total_response_time}"
            echo "$name_path|Global Request Processing Latency, value=${global_avg_request_processing_latency}"
            echo "$name_path|Global Average Target Response Time, value=${global_avg_target_response_time}"
            echo "$name_path|Average Total Response Time, value=${avg_total_response_time}"
            echo "$name_path|Average Target Response Time, value=${avg_target_response_time}"
            echo "$name_path|Average Request Processing Latency, value=${avg_request_processing_latency}"
         done < metrified_response.out

      #2.Processing HTTP Status Code Response Codes 
      jq -r  '.[].stats.data[]
      | [.identifier.values]
      | "\(.[0]) "
      ' < ${curl_output} | sed 's/"//g;s/[][]//g;s/,/ /g' >  jq_processed_status_code.out

      #jq_processed_status_code.out file format is is :
      # identifier[space]response_status_code[space]target_response_code"
      while read -r status_codes ; do
          identifier=$(echo ${status_codes} | awk '{print $1}')
          response_status_code=$(echo ${status_codes} | awk '{print $2}')
          target_response_code=$(echo ${status_codes} | awk '{print $3}')

          name_path="name=${metric_prefix}|${server_friendly_name}|${metric_base}|${environments}|${identifier}"

          echo "$name_path|Response Status Code|${response_status_code}, value=1"
          echo "$name_path|Target Response Code|${target_response_code}, value=1"
      done < jq_processed_status_code.out
      
        #clean up, but leave response.json to help troubleshoot any issues with this script and/or Apigee's response
     rm jq_processed_response.out metrified_response.out jq_processed_status_code.out

    #Send anaytics events 
    if (${enable_biq} -eq "true"); then 
       echo "BiQ is enabled, sending analytics events "
       source ./analytics/analytics_events.sh
    fi
   #end if host_url not null
   fi
 #end config.json loop
done
 
