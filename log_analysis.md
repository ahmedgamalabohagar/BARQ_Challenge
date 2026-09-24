# Log analysis

Use all three supplied logs. Answer every question with commands/scripts and actual output.

1. What UTC interval is covered? How many valid, malformed and duplicate lines are in each file?
    1-UTC interval
    **command**
    head -n 1 logs/access.log
    {"timestamp":"2026-08-20T11:00:00.015Z","request_id":"lab-000001","method":"GET","path":"/missing","status":404,"upstream":"172.23.0.11:8080","upstream_status":"404","request_time":0.015,"client":"192.0.2.24"}
    tail -n 1 logs/access.log
    {"timestamp":"2026-08-20T11:29:57.578Z","request_id":"lab-000720","method":"GET","path":"/","status":200,"upstream":"172.23.0.12:8080","upstream_status":"200","request_time":0.078,"client":"192.0.2.24"}

    **Result**
    # access.log : from "2026-08-20T11:00:00.015Z" to "2026-08-20T11:29:57.578Z"
    # application.log : from "timestamp":"2026-08-20T11:00:00.015Z" to "2026-08-20T11:29:57.578Z"
    # error.log : from "2026/08/20 11:05:02" to "2026/08/20 11:30:00 "
    ---------------------------------------------------------------
    **command**
    total --> wc -l logs/access.log  
    valid --> jq -Rc "fromjson?" access.log | wc -l 
    malformed --> total - valid 
    duplicated --> sort access.log | uniq -d | wc -l

    # File            |total | valid | malformed | duplicated 
    # access.log      | 726  |  725  | 1         | 5   (10)
    # application.log | 730  |  729  | 1         | 2   (4)
    # error.log       | 68   |  68   | 0         | 0           --> text file

    **challenge**
    when i use "jq -c '.' access.log | wc -l" command when it catch malformed line , it terminated and not continue remaining lines


2. How many distinct client requests occurred? How did you deduplicate and avoid counting retries twice?
**command**
jq -Rc 'fromjson?' logs/access.log | jq -r '.request_id // empty' | sort -u | wc -l
or
valid requests - duplicated = 725 - 5 = 720 
**result**
720 


3. What are the final client status counts and error rate? State your denominator.
**command**
jq -Rc 'fromjson?' access.log | sort -u | jq -r '.status' | sort | uniq -c

**result**
status-code |       description                 | count 
200         |  success {OK}                     | 620    
404         |  client-error(Not Found)          | 10    
502         |  server-error(Bad gateway)        | 40    
503         |  server-error(service unavailable)| 47    
504         |  server-error(Gateway Timeout)    | 8     

error rate = total error / total valid requests = 
            (10+40+47+8) / 725 * 100 = 14.48 %
server error rate = 97 / 725 * 100

4. Which paths, time windows and backends account for the failures?
**command**
- paths
 jq -R 'fromjson? | select(.status >= 400) | .path' access.log | sort | uniq -c
- time windows
  jq -R 'fromjson? | select(.status >= 400) | .timestamp[0:16]' access.log | sort | uniq -c 
- backends
 jq -Rr 'fromjson? | select(.status >= 400) | .upstream' access.log | sort | uniq -c
     
**results**
- paths    
10 "/"
26 "/counter"
10 "/health"
10 "/missing"
23 "/ready"
26 "/records"
- time windows
1 "2026-08-20T11:00"
1 "2026-08-20T11:03"
8 "2026-08-20T11:05"
9 "2026-08-20T11:06"
8 "2026-08-20T11:07"
8 "2026-08-20T11:08"
9 "2026-08-20T11:09"
8 "2026-08-20T11:12"
8 "2026-08-20T11:13"
8 "2026-08-20T11:14"
8 "2026-08-20T11:15"
1 "2026-08-20T11:16"
1 "2026-08-20T11:19"
8 "2026-08-20T11:20"
8 "2026-08-20T11:21"
1 "2026-08-20T11:23"
4 "2026-08-20T11:25"
5 "2026-08-20T11:26"
1 "2026-08-20T11:29"
- backends
32 172.23.0.11:8080
73 172.23.0.12:8080


5. What are the median and p95 client latencies? State the percentile method and units.
median = 725 * 0.5 = 362
p95 = 725 * 0.95 = 688
**command**
jq -R 'fromjson? | .request_time' access.log | sort  | sed -n '363p;689p
**result**
0.054
2.001


6. Which requests retried upstream? How many succeeded after retrying?
**which requests retried upstream**
jq -R 'fromjson? | select(.upstream | contains(",")) | .request_id' logs/access.log
**result**
"lab-000124"
"lab-000130"
"lab-000136"
"lab-000142"
"lab-000148"
"lab-000154"
"lab-000160"
"lab-000166"
"lab-000172"
"lab-000178"
"lab-000184"
"lab-000190"
"lab-000196"
"lab-000202"
"lab-000208"
"lab-000214"
"lab-000220"
"lab-000226"
"lab-000232"

**how many successed after retried**
jq -R 'fromjson? | select(.upstream | contains(",")) | .status' logs/access.log | sort | uniq -c
**result**
19 200
all of them success

7. Build an incident timeline using evidence from access, error AND application logs.
**commands**
cat logs/error.log 
jq -Rc 'fromjson? | select(.level == "ERROR" or .level == "WARN") ' logs/application.log
jq -Rc 'fromjson? | select(.status >= 500) ' logs/access.log

**Timeline**
11:00 -> 11:04 : all paths return ok 200
11:05 -> 11:09 : (error.log=connection refused) (access.log=badgateway 502) , (172.23.0.12:8080) crashed
11:05 -> 11:21 : all 19 succeeded with 200 OK , NGINX retried faild request on (172.23.0.11:8080)
11:12 -> 11:15 : 504 Gateway Timeout , (172.23.0.12:8080) become responsive again but have heavy latency
11:20 -> 11:26 : 503 Service Unavailable , (172.23.0.11:8080) became overloaded



8. Show one correlated failed request and one successful request. Include IDs and timestamps.
**command**
jq -Rr 'fromjson? | select(.request_id == "lab-000122")' logs/access.log
jq -Rr 'fromjson? | select(.request_id == "lab-000124")' logs/access.log

**result**
{"timestamp":"2026-08-20T11:05:02.503Z","request_id":"lab-000122","method":"GET","path":"/health","status":502,"upstream":"172.23.0.12:8080","upstream_status":"502","request_time":0.003,"client":"192.0.2.24"}
{"timestamp":"2026-08-20T11:05:07.620Z","request_id":"lab-000124","method":"GET","path":"/ready","status":200,"upstream":"172.23.0.12:8080, 172.23.0.11:8080","upstream_status":"502, 200","request_time":0.12,"client":"192.0.2.24"}

9. Which errors appear to be proxy/connectivity issues versus dependency/application issues? What proves it?
**proxy/connectivity**
status code = 502 bad gateway  
proves by : (error.log : connect() failed (111: Connection refused) , application.log : no log) 
**dependency/application**
status code = 504 gateway timeout  
proves by : application.log -> `request_time` reached `2.001s`
status code = 503 Service Unavailable 
proves by : The server (`172.23.0.11:8080`) got overloaded

10. What do the logs not prove? What would you check next in a running environment?
**logs not prove**
Exact Cause of Process Crash
Root Cause of Application Latency
Static log files do not reflect metrics , hardware faults or network packet loss.
**what is the next**
check Container Logs
check metrics
nginx config