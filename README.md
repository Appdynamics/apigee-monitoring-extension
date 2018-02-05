# Apigee Monitoring Extension for AppDynamics #
 #### For use with Apigee Edge on SaaS and on-premise ####
 
## Use Case ###

Apigee is an API management platform that enables developers and businesses to design, secure, deploy, monitor, and scale APIs. This extension makes it possible for AppDynamics customers to monitor the performance of Apigee API proxies (or services as some people prefer to call it).Apigee performance metrics in AppDynamics will help customers to quickly isolate the root cause of a performance issue - whether it is Apigee's overhead and/or the backend (target) service.  

**Metrics** that are collected for each API proxy are : 

1. **Response Time:**  Total number of milliseconds it took to respond to a call. This time includes the Apigee API proxy overhead and your target server time.
2. **Target Response Time:**  Number of milliseconds it took your target server to respond to a call. This number tells you how your own servers are behaving.
3. **Request Processing Latency:** Number of milliseconds from the time when a call reaches the selected API proxy to the time when Apigee sends the call to your target server.

## Prerequisite ###
1. This extension works only with the standalone Java machine agent. 
2. Create a service account in Apigee that has read access to all ALL the API proxies you would like to monitor in AppDynamics 
3. jq must be installed on the server running the machine agent - https://stedolan.github.io/jq/download/ 

### Installation ###
1. Unzip the attached file into $MACHINE_AGENT_HOME/monitors 
2. Using your favourite text editor, open apigee_monitor.sh and fill in these variables
* apigee_username
* apigee_password 
* organization
* environments
* host_name
3. Make the script executable:  `chmod +x apigee_monitor.sh` 
4. Test it: `./apigee_monitor.sh`
5. If everything is OK, you should see an output in stdout that is similar to this: 
   
>     ==> from 01/23/2018+22:53:40 to 01/23/2018+23:03:40 
>        curl -X GET   https://api.enterprise.apigee.com/v1/organizations/io/environments/test/stats/apiproxy?_optimized=js&realtime=true&limit=300&select=sum(message_count),avg(total_response_time),avg(target_response_time),avg(request_processing_latency),sum(is_error)&sort=DESC&sortby=sum(message_count),avg(total_response_time),sum(is_error)&timeRange=01/23/2018+22:53:40~01/23/2018+23:03:40&timeUnit=minute&tsAscending=true
> 
>      ==> 200
>      name=Custom Metrics|Apigee|Proxies|[proxy name]|Availability, value=1
>      name=Custom Metrics|Apigee|Proxies|[proxy name]|Average Response Time, value=501
>      name=Custom Metrics|Apigee|Proxies|[proxy name]|Request Processing Latency, value=25
>      name=Custom Metrics|Apigee|Proxies|[proxy name]|Target Response Time, value=474

6. Restart the machine agent 

###  Custom Dashboard ###
The custom dashboard below shows 2 API proxy performance metrics - with their respective SLAs 

<img src="https://user-images.githubusercontent.com/2548160/35309120-a9c619bc-00a2-11e8-9713-64d6e9e05381.png" alt="Dash" height="230" width="850"/>

Metrics are located in Application Infrastructure Performance | Tier_NAME| Custom Metrics | Apigee |* 

<img src="https://user-images.githubusercontent.com/2548160/35309333-d0f9fd54-00a3-11e8-8602-27231a0b8d4e.png" alt="Dash" height="450" width="400"/>


### Troubleshooting ###

review $MACHINE_AGENT_HOME/logs/apigee-monitor.log 

### Contribution guidelines ###

* Fork and submit PR 


