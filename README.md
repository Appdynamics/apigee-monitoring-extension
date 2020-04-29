# Apigee Monitoring Extension for AppDynamics #
 #### Tested with Apigee Edge ####
 
## Use Case ###

Apigee is an API management platform that enables developers and businesses to design, secure, deploy, monitor, and scale APIs. This extension makes it possible for AppDynamics customers to monitor the performance of Apigee API proxies.

The Apigee monitoring extension help AppDynamics customers to quickly isolate the root cause of performance issues - whether it is Apigee's overhead and/or the backend (target) service. The extension monitors API proxy performance metrics such as Total Error count, Traffic rate, Response Time and Error response codes. Also, it has an optional built-in feature to analyse and report on API proxy performance metrics using the AppDynamics BiQ platform - this gives customers the extra flexibility of slicing and dicing API proxy and target errors for reporting and continues enhancements purposes.

The extension now supports monitoring for multiple Apigee instances, environments and orgs - in any combination of your choice.
 
 The following Apigee proxy metrics are monitored by this AppDynamics monitoring solution: 

1. **Response Time:**  Total number of milliseconds it took to respond to a call. This time includes the Apigee API proxy overhead and your target server time.
2. **Target Response Time:**  Number of milliseconds it took your target server or service to respond to a call. This number tells you how your own services are behaving.
3. **Min and Max of Target Response Time:**  The Minimum and Maximum Target Response Time over in the given query period
4. **Overall Average Response Time:**  Overall Average Response Time for all proxies - it's calculated by summing the response times and divided by the number of proxies available at the time. 
5. **Request Processing Latency:** Number of milliseconds from the time when a call reaches the selected API proxy to the time when Apigee sends the call to your target server.
 **Min and Max of Processing Latency:**  The Minimum and Maximum Processing Latency values over the query period
6. **Traffic:** The number of recorded API requests for each API proxy
7. **Error:**  The total number of times API proxies failed over the specified period. Proxy failure can occur when a policy fails or when there's a runtime 
8. **Policy Error:**  The total number of times API proxy policy failed
9. **Error Count Sum:** Summation of errors for all API proxies  
10. **4XX Count:** The total number of 4XX HTTP Response Code for each API proxy 
11. **4XX Sum:** Summation of 4XX HTTP Response Codes in all API proxies
12. **5XX Count:** The total number of 5XX HTTP Response Code for each API proxy 
13. **5XX Sum:** Summation of 5XX HTTP Response Codes for all API proxies


## Prerequisite ###
1. This extension works only with the standalone Java machine agent. 
2. Analytics module must be enabled in Apigee 
2. Create a service account in Apigee that has read access to all ALL the API proxies you would like to monitor in AppDynamics 
3. jq must be installed on the server running the machine agent - https://stedolan.github.io/jq/download/ 

### Installation ###
1. Unzip the attached file into $MACHINE_AGENT_HOME/monitors 
2. Using your favourite text editor, open config.json and fill in the configuration properties:

  | **Config Property Name** | **Description** |
  | --- | --- |
  | host_url  | Apigee host url, including the port number if required. |
  | metric_prefix  | Define metrics prefix, for example:  `Server|Component:<tier-name>|Custom Metrics|Apigee ` . Please do not add `|` at the end. |
  | org  | Select the organization that contains the proxies you would like to monitor |
  | env  | Select the environment that contains the proxies you would like to monitor. prod, Dev, Prod, etc.  |
  | server_friendly_name  | An free text indicator that best describes your Apigee environment, org, or environment. use - or _ to separate words, not spaces |
  | username | Username of the read-only service account  |
  | password | Password of the read-only service account |
  | use_proxy-filter  | If set to true, the monitoring extension will only collect metrics for proxies that are defined in the `apipproxy.conf` file |
  | enable_BiQ  | If set to true, the monitoring extension will send proxy and target response codes to BiQ platform. This requires BiQ license|
  | analytics_endpoint  | This is the analytics endpoint of your controller. This differs depending on the location of your controller. Please refer to this [doc](https://docs.appdynamics.com/display/PAA/Onprem-DC1+Domains+and+IP+Ranges). |
  | global_account_name  | You can get the global account name to use from the [License page](https://docs.appdynamics.com/display/latest/License+Management)  |
  | analytics_key | Create the analytics API Key by following the instruction in this [doc](https://docs.appdynamics.com/display/latest/Managing+API+Keys).  Grant Manage, Query and Publish permissions to Custom |
  | proxy_url  | Define proxy host if in use, otherwise leave blank.  |
  | proxy_port | Define proxy port if `proxy_url` is not blank |

3. Version 2.0 and above of this extension support monitoring of multiple Apigee instances, environments or organisations. To do this, add an element to the connection details array as shown below. Note, use a unique `server_friendly_name` for each entry. 
`````
 {
      "host_url": "https://localhost:8080",
      "org": "customer1",
      "env": "prod",
      "server_friendly_name": "Onpremise-Sever001-DC1",
      "username": "username",
      "use_proxy_filter": true,
      "password": "password"
    }
`````
4. If `use_proxy_filter` is set to true, list the target proxies in the `apipproxy.conf` file - one item per line. 

  *Note: user_proxy_filter, when set to true will ONLY send API performance metrics for the predefined proxies in the
   apiproxy.conf file. If set to false, performance data for ALL apigee proxies in the `org` and `env` will be collected.* 

5. Test it: `./apigee_monitor.sh`
6. If everything is OK, you should see an output in stdout that is similar to this: 
`````
sending request to Apigee.... 
Using un-filtered request - collecting all proxy information
curl https://api.enterprise.apigee.com/v1/organizations/appd/environments/prod/stats/apiproxy,response_status_code,target_response_code?_optimized=js&realtime=true&limit=120&select=sum(message_count),avg(total_response_time),avg(target_response_time),avg(request_processing_latency),sum(is_error)&sort=DESC&sortby=sum(message_count),avg(total_response_time),sum(is_error)&timeRange=01/11/2020+18:13:43~01/11/2020+18:15:43&timeUnit=minute&tsAscending=true -u israelo@appd.com:******
==> 200
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Availability, value=1
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Total Message Count, value=16
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Total Error Count, value=2
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Total Policy Errors, value=0
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Total Target Errors, value=0
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Global Average Response Time, value=7222
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Average Total Response Time, value=5822
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Minimum Total Response Time, value=125
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Maximum Total Response Time, value=55145
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Global Request Processing Latency, value=1
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Average Request Processing Latency, value=1
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Minimum Request Processing Latency, value=0
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Maximum Request Processing Latency, value=2
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Global Average Target Response Time, value=7216
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Average Target Response Time, value=5815
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Minimum Target Response Time, value=120
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|Maximum Target Response Time, value=55142

Processing 4xx metrics for AppDynamics
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|4XX Count, value=2
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|Total 5XX, value=2

Processing 5xx metrics for AppDynamics
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|OAuth_v1|5XX Count, value=1
name=Server|Component:<tier-name>|Custom Metrics|Apigee|Onpremise-DC1|Proxies|prod|Total 5XX, value=1

`````
Do not proceed until you get an output similar to the above. 

6. Restart the machine agent 

Note: The Global* metric is synonymous with AppDynamics baseline metric. We recommend that you use the non-Global metrics for your health rule metrics. 

###  BiQ Output ###

If BiQ is enabled, you can now slice and dice Apigee metrics in many dimensions to suit your business needs, for example:  

`SELECT * FROM apigee_metrics WHERE total_response_time > 5 and four_xx > 0 and environment="prod" SINCE 2 hours`

![BiQ ](https://user-images.githubusercontent.com/2548160/76960791-12915c00-6914-11ea-99f1-c98865c83e85.png)

###  Custom Dashboard ###
The custom dashboard below shows 2 API proxy performance metrics - with their respective SLAs 

<img src="https://user-images.githubusercontent.com/2548160/35309120-a9c619bc-00a2-11e8-9713-64d6e9e05381.png" alt="Dash" height="230" width="850"/>

Metrics are located in Application Infrastructure Performance | Tier_NAME| Custom Metrics | Apigee |* 

<img src="https://user-images.githubusercontent.com/2548160/72211826-8bfe6f80-34c9-11ea-88e1-a79c4ddeabff.png" alt="Dash" height="390" width="900"/>

### Troubleshooting ###

1. Review $MACHINE_AGENT_HOME/logs/apigee-monitor.log 

2. Check the analytics page in Apigee and ensure you can see performance data for the proxy APIs in the correct org and env 

3. Send a manual curl request to your apigee instance to verify it's working

4. If you need to contact support, reload the Apigee analytics page, save [HTTP HAR file](https://community.appdynamics.com/t5/Knowledge-Base/How-do-I-create-a-HAR-File-to-troubleshoot-web-download-issues/ta-p/23373) and attach it to the support case. 

### Contribution guidelines ###

* Fork and submit PR 
