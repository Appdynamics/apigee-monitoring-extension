#!/bin/sh

#Author : Israel.Ogbole@appdynamics.com

#This extension sends the following Apigee metrics to AppDynamics

# 1) Response Time:	Total number of milliseconds it took to respond to a call. This time includes the Apigee API proxy overhead and your target server time.
# 2) Target Response Time:	Number of milliseconds it took your target server to respond to a call. This number tells you how your own servers are behaving.
# 3) Request Processing Latency:	Number of milliseconds from the time when a call reaches the selected API proxy to the time when Apigee sends the call to your target server.

#Refs:
#Explanation of metrics:  https://docs.apigee.com/analytics-services/content/latency-analysis-dashboard
#Meric API : https://docs.apigee.com/analytics-services/content/latency-analysis-dashboard

#===Update these variables==
organization=""
environments="test"  #apigee environment name.
apigee_username=""
apigee_password=""
# onpremise installation API URL is different from cloud, onpremise uses port 8080 i.e
#Ref : https://community.apigee.com/questions/3170/edge-management-api-url-for-on-premises.html
host_name="https://api.enterprise.apigee.com" # for onpremise installation use http(s)://<IP>:8080
#The organization and environments variable names returned 404 for an onpremise installation of apigee. Changing it to  'o' and 'e' in the curl cmd worked. I don't know why.
base_url="${host_name}/v1/organizations"

#This will create metrics in specific Tier/Component. Make sure to replace <tier_id> with the appropriate one from your environment.
#To find the tier_id in your environment, please follow the screenshot https://docs.appdynamics.com/display/PRO42/Build+a+Monitoring+Extension+Using+Java?preview=/34272441/34413993/componentid.png
#metric_prefix="Server|Component:<tier_id>|Custom Metrics|Apigee|${environments}"

#This will create metrics in all tiers of your business application
metric_prefix="Custom Metrics|Apigee|${environments}"
metric_base="Proxies"
proxy_conf_file_path="apiproxy.conf"
log_path="../../logs/apigee-monitor.log"

real_time=true
query_limit=300
timeUnit="minute" #A value of second, minute, hour, day, week, month, quarter, year, decade, century, millennium.
apiproxy_names=""

IOcURL() {
  [ -z "${curl_output}" ] && curl_output="response.json"
  [ -f "${curl_output}" ] && rm ${curl_output}
  echo "curl ${1}"
  # for added security, store your password in a file, and cat it like this $(cat .password), otherwise password will be visible in bash history
  # or use -n (.netrc) instead
  curl_response_code=$(curl -u ${apigee_username}:${apigee_password} -s -w "%{http_code}" -o "${curl_output}" -X GET "${1}")
  echo "==> ${curl_response_code}"
}

if [ ! -f "${proxy_conf_file_path}" ]; then
    msg="${proxy_conf_file_path} does not exist. \n This file is required for this extension to work.\
    Create a line delimited list of your api proxy names i.e one proxy per line and ensure you hit enter"
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

echo "==> Using the following proxies in the filter: \n ${apiproxy_names}"

#Use this if you're on Mac OS
#minutes_ago=$(date -r $(( $(date +%s) - 600 )) | awk '{print $4}')
#time_now=$(date +"%T")
#today=$(date +"%m/%d/%Y")
#to_range=$(echo ${today}+${time_now})
#from_range=$(echo ${today}+${minutes_ago})

#or this if you're on GNU - tested on Ubuntu, CentOS and Redhat 
to_range=$(date +%x+%H:%M:%S)
from_range=$(date +%x+%H:%M:%S --date='10 minutes ago')

echo "==> from ${from_range} to ${to_range}"

req="${base_url}/${organization}/environments/${environments}/stats/apiproxy?_optimized=js&realtime=${real_time}\
&limit=${query_limit}&select=sum(message_count),avg(total_response_time),avg(target_response_time),avg(request_processing_latency),sum(is_error)\
&sort=DESC&sortby=sum(message_count),avg(total_response_time),sum(is_error)&timeRange=${from_range}~${to_range}&timeUnit=${timeUnit}&tsAscending=true"

filtered_req="${base_url}/${organization}/environments/${environments}/stats/apiproxy?_optimized=js&realtime=${real_time}&filter=(apiproxy in ${apiproxy_names})\
&limit=${query_limit}&select=sum(message_count),avg(total_response_time),avg(target_response_time),avg(request_processing_latency),sum(is_error)\
&sort=DESC&sortby=sum(message_count),avg(total_response_time),sum(is_error)&timeRange=${from_range}~${to_range}&timeUnit=${timeUnit}&tsAscending=true"

#send the request to Apigee
IOcURL ${req} #use ${filtered_req} if you want to use the filtered request and ${req} for unfiltered

if [ "${curl_response_code}" -ne 200 ]; then
 msg="The request failed with ${curl_response_code} response code.\n \
 	  The requested URL is: ${req} \n \
 	  Apigee's Response is :\n   $(cat ${curl_output}) \n"
 echo "${msg}"
 echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >> ${log_path}
 exit 1
fi

if [ ! -f "${curl_output}" ]; then
  msg="The output of the cURL request wasn't saved. please ensure that $(whoami) user has write acccess to $(pwd). Exiting..."
  echo "${msg}"
  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] ${msg}" >> ${log_path}
  exit 1
fi

#check if identifier string is present in the output
if ! grep -q identifier "${curl_output}"; then
  msg="The request was successful, but Apigee didn't respond with any proxy info in the specified time range \n \
  Please make sure there are traffic - from ${from_range} to ${to_range}"
  echo "${msg}"
  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [ERROR] $msg" >> ${log_path}
  exit 1
fi

#now it's time for the fun bit that I always dread:)
 jq  -r '
    .[].stats.data[]
    | (.identifier.values[]) as $identifier
    | (.metric[]
       | select(.name == "global-avg-total_response_time")
       | .values
      ) as $avg_response_time
    | (.metric[]
       | select(.name == "global-avg-request_processing_latency")
       | .values
      ) as $request_processing_latency
       | (.metric[]
       | select(.name == "global-avg-target_response_time")
       | .values
      ) as $target_processing_latency
    | $identifier, $avg_response_time,$request_processing_latency,$target_processing_latency
    '< ${curl_output} | sed 's/[][]//g;/^$/d;s/^[ \t]*//;s/[ \t]*$//' > jq_processed_response.out

#tranpose the matrix of the metrics
#a=identifier
#b=aveg response time
#c=request processng latency
#d=target processing latency

awk 'NF>0{a=$0;getline b; getline c; getline d; print a FS b FS c FS d}' jq_processed_response.out > metrified_response.out

while read -r response_content ; do

  identifier=$(echo ${response_content} | awk '{print $1}')
  #round the values up to highest or lowest int->awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}'
  avg_response_time=$(echo ${response_content}  | awk '{print $2}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
  request_processing_latency=$(echo ${response_content}  | awk '{print $3}' | awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')
  target_processing_latency=$(echo ${response_content}  | awk '{print $4}' |awk '{print ($1-int($1)<0.499)?int($1):int($1)+1}')

  echo "name=${metric_prefix}|${metric_base}|${identifier}|Availability, value=1"
  echo "name=${metric_prefix}|${metric_base}|${identifier}|Average Response Time, value=${avg_response_time}"
  echo "name=${metric_prefix}|${metric_base}|${identifier}|Request Processing Latency, value=${request_processing_latency}"
  echo "name=${metric_prefix}|${metric_base}|${identifier}|Target Response Time, value=${target_processing_latency}"

done < metrified_response.out

#clean up, but leave response.json to help troubleshoot any issues with this script and/or Apigee's response
rm jq_processed_response.out metrified_response.out
