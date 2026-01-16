#!/bin/bash

# Task 1: Configure a health check firewall rule
# This script creates a firewall rule to allow health check traffic from Google Cloud Load Balancers

echo "Creating health check firewall rule..."

gcloud compute firewall-rules create fw-allow-health-checks \
    --network=default \
    --action=allow \
    --direction=ingress \
    --target-tags=allow-health-checks \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --rules=tcp:80

echo "Health check firewall rule created successfully!"

# Verify the firewall rule
echo "Verifying firewall rule..."
gcloud compute firewall-rules describe fw-allow-health-checks

echo ""
echo "=========================================="
echo "Task 2: Create a NAT configuration using Cloud Router"
echo "=========================================="

# Create Cloud Router
echo "Creating Cloud Router..."
gcloud compute routers create nat-router-us1 \
    --network=default \
    --region=us-east1

echo "Cloud Router created successfully!"

# Create Cloud NAT gateway
echo "Creating Cloud NAT gateway..."
gcloud compute routers nats create nat-config \
    --router=nat-router-us1 \
    --region=us-east1 \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges

echo "Cloud NAT gateway created successfully!"

# Verify the NAT configuration
echo "Verifying Cloud NAT configuration..."
gcloud compute routers nats describe nat-config \
    --router=nat-router-us1 \
    --region=us-east1

echo ""
echo "=========================================="
echo "Task 3: Create a custom image for a web server"
echo "=========================================="

# Create a VM instance for the web server
echo "Creating web server VM instance..."
gcloud compute instances create webserver \
    --zone=us-east1-d \
    --machine-type=e2-medium \
    --network-interface=subnet=default,no-address \
    --tags=allow-health-checks \
    --boot-disk-auto-delete=no \
    --metadata=startup-script='#! /bin/bash
apt-get update
apt-get install -y apache2
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head><title>Web Server</title></head>
<body>
<h1>Welcome to the Web Server</h1>
<p>Hostname: $(hostname)</p>
<p>Zone: $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone -s | cut -d/ -f4)</p>
</body>
</html>
EOF
systemctl restart apache2'

echo "Web server VM instance creation initiated!"
echo "Waiting for instance to be ready..."

# Wait for the instance to be in RUNNING state
sleep 10
gcloud compute instances describe webserver --zone=us-east1-d --format="value(status)" || echo "Instance is still being created..."

echo "Web server VM instance is ready!"

# Wait for the instance to fully initialize
echo "Waiting for web server to fully initialize..."
sleep 60

# Stop the instance before creating image
echo "Stopping webserver instance..."
gcloud compute instances stop webserver --zone=us-east1-d

echo "Webserver stopped successfully!"

# Create custom image from the webserver instance
echo "Creating custom image from webserver..."
gcloud compute images create mywebserver \
    --source-disk=webserver \
    --source-disk-zone=us-east1-d \
    --family=webserver-family

echo "Custom image created successfully!"

echo ""
echo "=========================================="
echo "Task 4: Configure an instance template and create instance groups"
echo "=========================================="

# Create instance template
echo "Creating instance template..."
gcloud compute instance-templates create mywebserver-template \
    --machine-type=e2-micro \
    --network-interface=subnet=default,no-address \
    --tags=allow-health-checks \
    --image=mywebserver \
    --image-project=$(gcloud config get-value project) \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard

echo "Instance template created successfully!"

# Create health check for managed instance groups
echo "Creating health check for managed instance groups..."
gcloud compute health-checks create tcp http-health-check \
    --port=80

echo "Health check created successfully!"

# Create managed instance group in us-east1
echo "Creating managed instance group in us-east1..."
gcloud compute instance-groups managed create us-1-mig \
    --template=mywebserver-template \
    --size=1 \
    --zones=us-east1-b,us-east1-c,us-east1-d \
    --health-check=http-health-check \
    --initial-delay=60

echo "Managed instance group us-1-mig created successfully!"

# Configure autoscaling for us-1-mig
echo "Configuring autoscaling for us-1-mig..."
gcloud compute instance-groups managed set-autoscaling us-1-mig \
    --region=us-east1 \
    --min-num-replicas=1 \
    --max-num-replicas=2 \
    --target-load-balancing-utilization=0.8 \
    --cool-down-period=60

echo "Autoscaling configured for us-1-mig!"

# Create managed instance group in europe-west4
echo "Creating managed instance group in europe-west4..."
gcloud compute instance-groups managed create notus-1-mig \
    --template=mywebserver-template \
    --size=1 \
    --zones=europe-west4-a,europe-west4-b,europe-west4-c \
    --health-check=http-health-check \
    --initial-delay=60

echo "Managed instance group notus-1-mig created successfully!"

# Configure autoscaling for notus-1-mig
echo "Configuring autoscaling for notus-1-mig..."
gcloud compute instance-groups managed set-autoscaling notus-1-mig \
    --region=europe-west4 \
    --min-num-replicas=1 \
    --max-num-replicas=2 \
    --target-load-balancing-utilization=0.8 \
    --cool-down-period=60

echo "Autoscaling configured for notus-1-mig!"

# Set named ports for us-1-mig
echo "Setting named port for us-1-mig..."
gcloud compute instance-groups managed set-named-ports us-1-mig \
    --region=us-east1 \
    --named-ports=http:80

echo "Named port set for us-1-mig!"

# Set named ports for notus-1-mig
echo "Setting named port for notus-1-mig..."
gcloud compute instance-groups managed set-named-ports notus-1-mig \
    --region=europe-west4 \
    --named-ports=http:80

echo "Named port set for notus-1-mig!"

# Verify the managed instance groups
echo "Verifying managed instance groups..."
gcloud compute instance-groups managed list

echo ""
echo "Task 4 completed successfully!"

echo ""
echo "=========================================="
echo "Task 5: Configure the Application Load Balancer (HTTP)"
echo "=========================================="

# Create backend service
if gcloud compute backend-services describe http-backend --global &>/dev/null; then
    echo "Backend service http-backend already exists. Skipping creation..."
else
    echo "Creating backend service..."
    gcloud compute backend-services create http-backend \
        --protocol=HTTP \
        --port-name=http \
        --health-checks=http-health-check \
        --global \
        --enable-logging \
        --logging-sample-rate=1.0 \
        --load-balancing-scheme=EXTERNAL
    echo "Backend service created successfully!"
fi

# Add us-1-mig as backend
if gcloud compute backend-services describe http-backend --global --format="value(backends)" 2>/dev/null | grep -q "us-1-mig"; then
    echo "us-1-mig already added to backend service. Skipping..."
else
    echo "Adding us-1-mig as backend..."
    gcloud compute backend-services add-backend http-backend \
        --instance-group=us-1-mig \
        --instance-group-region=us-east1 \
        --balancing-mode=RATE \
        --max-rate-per-instance=50 \
        --capacity-scaler=1.0 \
        --global
    echo "us-1-mig added to backend service!"
fi

# Add notus-1-mig as backend
if gcloud compute backend-services describe http-backend --global --format="value(backends)" 2>/dev/null | grep -q "notus-1-mig"; then
    echo "notus-1-mig already added to backend service. Skipping..."
else
    echo "Adding notus-1-mig as backend..."
    gcloud compute backend-services add-backend http-backend \
        --instance-group=notus-1-mig \
        --instance-group-region=europe-west4 \
        --balancing-mode=UTILIZATION \
        --max-utilization=0.8 \
        --capacity-scaler=1.0 \
        --global
    echo "notus-1-mig added to backend service!"
fi

# Create URL map
if gcloud compute url-maps describe http-lb --global &>/dev/null; then
    echo "URL map http-lb already exists. Skipping creation..."
else
    echo "Creating URL map..."
    gcloud compute url-maps create http-lb \
        --default-service=http-backend
    echo "URL map created successfully!"
fi

# Create target HTTP proxy
if gcloud compute target-http-proxies describe http-lb-target-proxy --global &>/dev/null; then
    echo "Target HTTP proxy http-lb-target-proxy already exists. Skipping creation..."
else
    echo "Creating target HTTP proxy..."
    gcloud compute target-http-proxies create http-lb-target-proxy \
        --url-map=http-lb
    echo "Target HTTP proxy created successfully!"
fi

# Reserve IPv4 address
if gcloud compute addresses describe http-lb-ipv4 --global &>/dev/null; then
    echo "IPv4 address already reserved. Skipping..."
else
    echo "Reserving IPv4 address..."
    gcloud compute addresses create http-lb-ipv4 \
        --ip-version=IPV4 \
        --global
    echo "IPv4 address reserved!"
fi

# Reserve IPv6 address
if gcloud compute addresses describe http-lb-ipv6 --global &>/dev/null; then
    echo "IPv6 address already reserved. Skipping..."
else
    echo "Reserving IPv6 address..."
    gcloud compute addresses create http-lb-ipv6 \
        --ip-version=IPV6 \
        --global
    echo "IPv6 address reserved!"
fi

# Create global forwarding rule for IPv4 (Frontend Configuration)
if gcloud compute forwarding-rules describe http-lb-forwarding-rule --global &>/dev/null; then
    echo "IPv4 forwarding rule already exists. Skipping creation..."
else
    echo "Creating frontend configuration - IPv4 forwarding rule..."
    gcloud compute forwarding-rules create http-lb-forwarding-rule \
        --address=http-lb-ipv4 \
        --global \
        --target-http-proxy=http-lb-target-proxy \
        --ports=80
    echo "IPv4 frontend created successfully!"
fi

# Create global forwarding rule for IPv6 (Frontend Configuration)
if gcloud compute forwarding-rules describe http-lb-forwarding-rule-ipv6 --global &>/dev/null; then
    echo "IPv6 forwarding rule already exists. Skipping creation..."
else
    echo "Creating frontend configuration - IPv6 forwarding rule..."
    gcloud compute forwarding-rules create http-lb-forwarding-rule-ipv6 \
        --address=http-lb-ipv6 \
        --global \
        --target-http-proxy=http-lb-target-proxy \
        --ports=80
    echo "IPv6 frontend created successfully!"
fi

# Get the load balancer IP addresses
echo ""
echo "=========================================="
echo "Load Balancer Configuration Complete!"
echo "=========================================="
echo ""
echo "Getting load balancer IP addresses..."

LB_IP_v4=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule --global --format="value(IPAddress)")
LB_IP_v6=$(gcloud compute forwarding-rules describe http-lb-forwarding-rule-ipv6 --global --format="value(IPAddress)")

echo "Load Balancer IPv4 Address: $LB_IP_v4"
echo "Load Balancer IPv6 Address: $LB_IP_v6"
echo ""
echo "You can access your load balancer at:"
echo "  http://$LB_IP_v4"
echo ""

# Verify backend service configuration
echo "Verifying backend service..."
gcloud compute backend-services describe http-backend --global

echo ""
echo "Task 5 completed successfully!"
echo ""
echo "Note: It may take several minutes for the load balancer to become fully operational."
