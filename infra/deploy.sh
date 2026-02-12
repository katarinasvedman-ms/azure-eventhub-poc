#!/bin/bash

################################################################################
# Azure Event Hub Bicep Deployment Script
#
# Deploys an Azure Event Hub (Standard SKU) with 24 partitions,
# storage account for checkpointing, and consumer groups
#
# Usage: ./deploy.sh -g <ResourceGroupName> [-l <Location>] [-e <Environment>] [-s <Subscription>]
################################################################################

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Defaults
LOCATION="eastus"
ENVIRONMENT="dev"
SUBSCRIPTION=""

# Parse arguments
while getopts "g:l:e:s:h" opt; do
    case $opt in
        g) RESOURCE_GROUP_NAME="$OPTARG" ;;
        l) LOCATION="$OPTARG" ;;
        e) ENVIRONMENT="$OPTARG" ;;
        s) SUBSCRIPTION="$OPTARG" ;;
        h)
            echo "Usage: $0 -g <ResourceGroupName> [-l <Location>] [-e <Environment>] [-s <Subscription>]"
            echo ""
            echo "Options:"
            echo "  -g  Resource group name (REQUIRED)"
            echo "  -l  Azure region (default: eastus)"
            echo "  -e  Environment: dev, test, prod (default: dev)"
            echo "  -s  Azure subscription ID or name (optional)"
            echo "  -h  Show this help message"
            exit 0
            ;;
        *)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$RESOURCE_GROUP_NAME" ]; then
    echo -e "${RED}✗ Resource group name is required (-g)${NC}"
    exit 1
fi

# Print header
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                   Azure Event Hub Bicep Deployment Script                      ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Validate prerequisites
echo -e "${YELLOW}🔍 Validating prerequisites...${NC}"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}✗ Azure CLI not found. Please install: https://learn.microsoft.com/cli/azure/install-azure-cli${NC}"
    exit 1
fi
AZ_VERSION=$(az version --query '."azure-cli"' -o tsv)
echo -e "${GREEN}✓ Azure CLI version: $AZ_VERSION${NC}"

# Check Bicep CLI
if ! az bicep version &> /dev/null; then
    echo -e "${YELLOW}⚠ Bicep CLI not found. Installing...${NC}"
    az bicep install
fi
echo -e "${GREEN}✓ Bicep CLI available${NC}"

# Check template files
if [ ! -f "main.bicep" ]; then
    echo -e "${RED}✗ main.bicep not found in current directory${NC}"
    exit 1
fi
echo -e "${GREEN}✓ main.bicep found${NC}"

if [ ! -f "parameters.$ENVIRONMENT.json" ]; then
    echo -e "${RED}✗ parameters.$ENVIRONMENT.json not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ parameters.$ENVIRONMENT.json found${NC}"

echo ""

# Set subscription if provided
if [ ! -z "$SUBSCRIPTION" ]; then
    echo -e "${YELLOW}🔑 Setting subscription...${NC}"
    az account set --subscription "$SUBSCRIPTION"
    echo -e "${GREEN}✓ Subscription set${NC}"
fi

# Get current subscription info
CURRENT_SUB=$(az account show -o json)
SUB_NAME=$(echo $CURRENT_SUB | grep -o '"name":"[^"]*' | cut -d'"' -f4)
SUB_ID=$(echo $CURRENT_SUB | grep -o '"id":"[^"]*' | cut -d'"' -f4)
echo -e "${CYAN}📋 Current subscription: $SUB_NAME ($SUB_ID)${NC}"

echo ""

# Create resource group
echo -e "${YELLOW}📁 Creating resource group...${NC}"
RG=$(az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" -o json)
RG_LOCATION=$(echo $RG | grep -o '"location":"[^"]*' | cut -d'"' -f4)
echo -e "${GREEN}✓ Resource group created/verified: $RESOURCE_GROUP_NAME${NC}"
echo -e "${CYAN}  Location: $RG_LOCATION${NC}"

echo ""

# Validate Bicep template
echo -e "${YELLOW}🔎 Validating Bicep template...${NC}"
if ! az deployment group validate \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file main.bicep \
    --parameters "parameters.$ENVIRONMENT.json" \
    --parameters environment="$ENVIRONMENT" > /dev/null; then
    echo -e "${RED}✗ Template validation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Template validation passed${NC}"

echo ""

# Deploy
echo -e "${YELLOW}🚀 Deploying Event Hub infrastructure...${NC}"
echo -e "${CYAN}   Template: main.bicep${NC}"
echo -e "${CYAN}   Parameters: parameters.$ENVIRONMENT.json${NC}"
echo -e "${CYAN}   Environment: $ENVIRONMENT${NC}"
echo ""

DEPLOYMENT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file main.bicep \
    --parameters "parameters.$ENVIRONMENT.json" \
    --parameters environment="$ENVIRONMENT" \
    -o json)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment completed successfully${NC}"
else
    echo -e "${RED}✗ Deployment failed${NC}"
    exit 1
fi

echo ""

# Extract outputs
echo -e "${YELLOW}📤 Deployment Outputs:${NC}"
echo ""

EVENT_HUB_NS=$(echo $DEPLOYMENT | grep -o '"eventHubNamespaceName":{"value":"[^"]*' | cut -d'"' -f8)
EVENT_HUB_NAME=$(echo $DEPLOYMENT | grep -o '"eventHubName":{"value":"[^"]*' | cut -d'"' -f8)
PARTITION_COUNT=$(echo $DEPLOYMENT | grep -o '"partitionCount":{"value":[0-9]*' | cut -d':' -f4)
STORAGE_ACCOUNT=$(echo $DEPLOYMENT | grep -o '"storageAccountName":{"value":"[^"]*' | cut -d'"' -f8)
SEND_CONN_STR=$(echo $DEPLOYMENT | grep -o '"sendPolicyConnectionString":{"value":"[^"]*' | cut -d'"' -f8)
LISTEN_CONN_STR=$(echo $DEPLOYMENT | grep -o '"listenPolicyConnectionString":{"value":"[^"]*' | cut -d'"' -f8)
STORAGE_CONN_STR=$(echo $DEPLOYMENT | grep -o '"storageAccountConnectionString":{"value":"[^"]*' | cut -d'"' -f8)

echo -e "${CYAN}Event Hub Namespace:${NC}"
echo -e "${NC}  Name: $EVENT_HUB_NS"
echo -e "${CYAN}  Region: $LOCATION${NC}"
echo ""

echo -e "${CYAN}Event Hub Details:${NC}"
echo -e "${NC}  Hub Name: $EVENT_HUB_NAME"
echo -e "${NC}  Partitions: $PARTITION_COUNT"
echo -e "${CYAN}  Retention: 1 day${NC}"
echo ""

echo -e "${CYAN}Storage Account:${NC}"
echo -e "${NC}  Name: $STORAGE_ACCOUNT"
echo -e "${CYAN}  Container: checkpoints${NC}"
echo ""

echo -e "${CYAN}Connection Strings:${NC}"
echo -e "${NC}  Producer (Send):"
echo -e "${CYAN}  $SEND_CONN_STR${NC}"
echo ""
echo -e "${NC}  Consumer (Listen):"
echo -e "${CYAN}  $LISTEN_CONN_STR${NC}"
echo ""
echo -e "${NC}  Storage Account:"
echo -e "${CYAN}  $STORAGE_CONN_STR${NC}"
echo ""

# Create appsettings fragment
echo -e "${YELLOW}📝 Creating appsettings.json configuration fragment...${NC}"

CONFIG_FILE="appsettings.generated.json"

cat > "$CONFIG_FILE" << EOF
{
  "EventHub": {
    "FullyQualifiedNamespace": "$EVENT_HUB_NS.servicebus.windows.net",
    "EventHubName": "$EVENT_HUB_NAME",
    "ProducerConnectionString": "$SEND_CONN_STR",
    "ConsumerConnectionString": "$LISTEN_CONN_STR",
    "BatchSize": 100,
    "BatchTimeoutMs": 1000
  },
  "Storage": {
    "ConnectionString": "$STORAGE_CONN_STR",
    "ContainerName": "checkpoints"
  }
}
EOF

echo -e "${GREEN}✓ Configuration saved to: $CONFIG_FILE${NC}"
echo ""

# Final summary
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                         ✓ Deployment Successful!                              ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}🎯 Next Steps:${NC}"
echo ""
echo "1. Update your appsettings.json with configuration from appsettings.generated.json"
echo "   Copy the EventHub and Storage sections into your appsettings.json"
echo ""
echo "2. Run your producer/consumer application:"
echo "   dotnet run --configuration Release"
echo ""
echo "3. Monitor in Azure Portal:"
echo "   https://portal.azure.com/#resource/subscriptions/$SUB_ID/resourceGroups/$RESOURCE_GROUP_NAME"
echo ""
echo "4. View metrics:"
echo "   Event Hub → Metrics → Incoming/Outgoing Messages"
echo ""
echo "5. Load test (optional):"
echo "   k6 run load-test.js"
echo ""

echo -e "${GREEN}✓ Done!${NC}"
