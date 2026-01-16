#!/bin/bash

export ZONE=us-east1-b

export REGION_2=asia-east1

export REGION="${ZONE%-*}"

DEVSHELL_PROJECT_ID=$(gcloud config get-value project)
TOKEN=$(gcloud auth application-default print-access-token)

# Create firewall rule for health checks
gcloud compute --project=$DEVSHELL_PROJECT_ID firewall-rules create fw-allow-health-checks \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=allow-health-checks

# Create NAT router
gcloud compute routers create nat-router-us1 \
    --network=default \
    --region=$REGION

# Configure NAT
gcloud compute routers nats create nat-config \
    --router=nat-router-us1 \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges \
    --region=$REGION

sleep 60

# Create webserver instance
gcloud compute instances create webserver \
    --project=$DEVSHELL_PROJECT_ID \
    --zone=$ZONE \
    --machine-type=e2-medium \
    --network-interface=stack-type=IPV4_ONLY,subnet=default,no-address \
    --metadata=startup-script='sudo apt-get update
sudo apt-get install -y apache2
sudo update-rc.d apache2 enable
sudo service apache2 status',enable-oslogin=true \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --tags=allow-health-checks \
    --create-disk=boot=yes,device-name=webserver,image=projects/debian-cloud/global/images/debian-10-buster-v20240312,mode=rw,size=10,type=projects/$DEVSHELL_PROJECT_ID/zones/$ZONE/diskTypes/pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any

# Stop webserver to create image
gcloud compute instances stop webserver --zone=$ZONE --quiet

# Create custom image
gcloud compute images create mywebserver \
    --project=$DEVSHELL_PROJECT_ID \
    --source-disk=webserver \
    --source-disk-zone=$ZONE \
    --storage-location=us

# Start webserver again
gcloud compute instances start webserver --zone=$ZONE --quiet

# Create instance template
gcloud beta compute instance-templates create mywebserver-template \
    --project=$DEVSHELL_PROJECT_ID \
    --machine-type=e2-micro \
    --network-interface=network=default,no-address \
    --metadata=enable-oslogin=true \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --tags=allow-health-checks \
    --create-disk=auto-delete=yes,boot=yes,device-name=mywebserver-template,image=projects/$DEVSHELL_PROJECT_ID/global/images/mywebserver,mode=rw,size=10,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --reservation-affinity=any

# Create health check
gcloud beta compute health-checks create tcp http-health-check \
    --project=$DEVSHELL_PROJECT_ID \
    --port=80 \
    --proxy-header=NONE \
    --no-enable-logging \
    --check-interval=5 \
    --timeout=5 \
    --unhealthy-threshold=2 \
    --healthy-threshold=2

# Create US managed instance group with autoscaling
gcloud beta compute instance-groups managed create us-1-mig \
    --project=$DEVSHELL_PROJECT_ID \
    --base-instance-name=us-1-mig \
    --size=1 \
    --template=projects/$DEVSHELL_PROJECT_ID/global/instanceTemplates/mywebserver-template \
    --zones=$REGION-c,$REGION-b,$REGION-a \
    --target-distribution-shape=EVEN \
    --instance-redistribution-type=PROACTIVE \
    --list-managed-instances-results=PAGELESS \
    --health-check=projects/$DEVSHELL_PROJECT_ID/global/healthChecks/http-health-check \
    --initial-delay=60 \
    --no-force-update-on-repair \
    --default-action-on-vm-failure=repair \
    --standby-policy-mode=manual

gcloud beta compute instance-groups managed set-autoscaling us-1-mig \
    --project=$DEVSHELL_PROJECT_ID \
    --region=$REGION \
    --cool-down-period=60 \
    --max-num-replicas=2 \
    --min-num-replicas=1 \
    --mode=on \
    --target-load-balancing-utilization=0.8

# Create Asia managed instance group with autoscaling
gcloud beta compute instance-groups managed create notus-1-mig \
    --project=$DEVSHELL_PROJECT_ID \
    --base-instance-name=notus-1-mig \
    --size=1 \
    --template=projects/$DEVSHELL_PROJECT_ID/global/instanceTemplates/mywebserver-template \
    --zones=$REGION_2-a,$REGION_2-b,$REGION_2-c \
    --target-distribution-shape=EVEN \
    --instance-redistribution-type=PROACTIVE \
    --list-managed-instances-results=PAGELESS \
    --health-check=projects/$DEVSHELL_PROJECT_ID/global/healthChecks/http-health-check \
    --initial-delay=60 \
    --no-force-update-on-repair \
    --default-action-on-vm-failure=repair \
    --standby-policy-mode=manual

gcloud beta compute instance-groups managed set-autoscaling notus-1-mig \
    --project=$DEVSHELL_PROJECT_ID \
    --region=$REGION_2 \
    --cool-down-period=60 \
    --max-num-replicas=2 \
    --min-num-replicas=1 \
    --mode=on \
    --target-load-balancing-utilization=0.8

# Wait for instance groups to be ready
sleep 30

# Set named ports for US instance group
gcloud compute instance-groups set-named-ports us-1-mig \
    --named-ports http:80 \
    --region=$REGION

# Set named ports for Asia instance group
gcloud compute instance-groups set-named-ports notus-1-mig \
    --named-ports http:80 \
    --region=$REGION_2

sleep 30

# Create security policy
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "description": "Default security policy for: http-backend",
    "name": "default-security-policy-for-backend-service-http-backend",
    "rules": [
      {
        "action": "allow",
        "match": {
          "config": {
            "srcIpRanges": ["*"]
          },
          "versionedExpr": "SRC_IPS_V1"
        },
        "priority": 2147483647
      },
      {
        "action": "throttle",
        "description": "Default rate limiting rule",
        "match": {
          "config": {
            "srcIpRanges": ["*"]
          },
          "versionedExpr": "SRC_IPS_V1"
        },
        "priority": 2147483646,
        "rateLimitOptions": {
          "conformAction": "allow",
          "enforceOnKey": "IP",
          "exceedAction": "deny(403)",
          "rateLimitThreshold": {
            "count": 500,
            "intervalSec": 60
          }
        }
      }
    ]
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/securityPolicies"

sleep 30

# Create backend service
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "backends": [
      {
        "balancingMode": "RATE",
        "capacityScaler": 1,
        "group": "projects/'"$DEVSHELL_PROJECT_ID"'/regions/'"$REGION"'/instanceGroups/us-1-mig",
        "maxRatePerInstance": 50
      },
      {
        "balancingMode": "UTILIZATION",
        "capacityScaler": 1,
        "group": "projects/'"$DEVSHELL_PROJECT_ID"'/regions/'"$REGION_2"'/instanceGroups/notus-1-mig",
        "maxUtilization": 0.8
      }
    ],
    "cdnPolicy": {
      "cacheKeyPolicy": {
        "includeHost": true,
        "includeProtocol": true,
        "includeQueryString": true
      },
      "cacheMode": "CACHE_ALL_STATIC",
      "clientTtl": 3600,
      "defaultTtl": 3600,
      "maxTtl": 86400,
      "negativeCaching": false,
      "serveWhileStale": 0
    },
    "compressionMode": "DISABLED",
    "connectionDraining": {
      "drainingTimeoutSec": 300
    },
    "description": "",
    "enableCDN": true,
    "healthChecks": [
      "projects/'"$DEVSHELL_PROJECT_ID"'/global/healthChecks/http-health-check"
    ],
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "localityLbPolicy": "ROUND_ROBIN",
    "logConfig": {
      "enable": true,
      "sampleRate": 1
    },
    "name": "http-backend",
    "portName": "http",
    "protocol": "HTTP",
    "securityPolicy": "projects/'"$DEVSHELL_PROJECT_ID"'/global/securityPolicies/default-security-policy-for-backend-service-http-backend",
    "sessionAffinity": "NONE",
    "timeoutSec": 30
  }' \
  "https://compute.googleapis.com/compute/beta/projects/$DEVSHELL_PROJECT_ID/global/backendServices"

sleep 30

# Set security policy for backend service
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "securityPolicy": "projects/'"$DEVSHELL_PROJECT_ID"'/global/securityPolicies/default-security-policy-for-backend-service-http-backend"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/backendServices/http-backend/setSecurityPolicy"

sleep 30

# Create URL map
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "defaultService": "projects/'"$DEVSHELL_PROJECT_ID"'/global/backendServices/http-backend",
    "name": "http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/urlMaps"

sleep 30

# Create target HTTP proxy
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "http-lb-target-proxy",
    "urlMap": "projects/'"$DEVSHELL_PROJECT_ID"'/global/urlMaps/http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/targetHttpProxies"

sleep 30

# Create forwarding rule (IPv4)
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "IPProtocol": "TCP",
    "ipVersion": "IPV4",
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "name": "http-lb-forwarding-rule",
    "networkTier": "PREMIUM",
    "portRange": "80",
    "target": "projects/'"$DEVSHELL_PROJECT_ID"'/global/targetHttpProxies/http-lb-target-proxy"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/forwardingRules"

sleep 30

# Create target HTTP proxy (IPv6)
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "http-lb-target-proxy-2",
    "urlMap": "projects/'"$DEVSHELL_PROJECT_ID"'/global/urlMaps/http-lb"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/targetHttpProxies"

sleep 30

# Create forwarding rule (IPv6)
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "IPProtocol": "TCP",
    "ipVersion": "IPV6",
    "loadBalancingScheme": "EXTERNAL_MANAGED",
    "name": "http-lb-forwarding-rule-2",
    "networkTier": "PREMIUM",
    "portRange": "80",
    "target": "projects/'"$DEVSHELL_PROJECT_ID"'/global/targetHttpProxies/http-lb-target-proxy-2"
  }' \
  "https://compute.googleapis.com/compute/v1/projects/$DEVSHELL_PROJECT_ID/global/forwardingRules"

sleep 30

# Get load balancer IP
LB_IP_ADDRESS=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule --global --format="value(IPAddress)")

# Wait for load balancer to be ready
LB_IP=$LB_IP_ADDRESS
while [ -z "$RESULT" ]; do
  echo "Waiting for Load Balancer"
  sleep 5
  RESULT=$(curl -m1 -s $LB_IP | grep Apache)
done

# Create stress test instance
gcloud compute instances create stress-test \
    --project=$DEVSHELL_PROJECT_ID \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
    --metadata=enable-oslogin=true \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --create-disk=auto-delete=yes,boot=yes,device-name=stress-test,image=projects/$DEVSHELL_PROJECT_ID/global/images/mywebserver,mode=rw,size=10,type=projects/$DEVSHELL_PROJECT_ID/zones/$ZONE/diskTypes/pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any

# Run stress test
gcloud compute ssh --zone "$ZONE" "stress-test" --project "$DEVSHELL_PROJECT_ID" --quiet --command "sudo apt-get -y install apache2-utils && export LB_IP=$LB_IP_ADDRESS && ab -n 500000 -c 1000 http://\$LB_IP/"
