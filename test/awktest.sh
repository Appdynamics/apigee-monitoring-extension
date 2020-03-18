awk 'NF>0{a=$0 ;getline b; getline c; getline d; getline e; getline f; getline g; getline h; getline i;
    print a| FS b FS c FS d FS e FS f FS g FS h FS i}' jq_processed_response.out > metrified.out