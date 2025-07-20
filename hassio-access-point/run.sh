#!/usr/bin/with-contenv bashio

# SIGTERM-handler this funciton will be executed when the container receives the SIGTERM signal (when stopping)
term_handler(){
    logger "Stopping Hass.io Access Point" 0
    ip link set $WIFI_INTERFACE down
    ip link set $ETH_INTERFACE down
    ip link set br0 down
    ip link set $WIFI_INTERFACE nomaster
    ip link set $ETH_INTERFACE nomaster
    ip link delete br0 type bridge
    ip link set $ETH_INTERFACE up
    ip link set $WIFI_INTERFACE up
    exit 0
}

# Logging function to set verbosity of output to addon log
logger(){
    msg=$1
    level=$2
    #if [ $DEBUG -ge $level ]; then
    echo $msg
    #fi
}

CONFIG_PATH=/data/options.json

# Convert integer configs to boolean, to avoid a breaking old configs
declare -r bool_configs=( hide_ssid client_internet_access dhcp )
for i in $bool_configs ; do
    if bashio::config.true $i || bashio::config.false $i ; then
        continue
    elif [ $config_value -eq 0 ] ; then
        bashio::addon.option $config_value false
    else
        bashio::addon.option $config_value true
    fi
done

# Setup signal handlers
trap 'term_handler' EXIT

SSID=$(bashio::config "ssid")
WPA_PASSPHRASE=$(bashio::config "wpa_passphrase")
WIFI_INTERFACE=$(bashio::config "wifi_interface")
ETH_INTERFACE=$(bashio::config "eth_interface")
HIDE_SSID=$(bashio::config.false "hide_ssid"; echo $?)
ALLOW_MAC_ADDRESSES=$(bashio::config 'allow_mac_addresses' )
DENY_MAC_ADDRESSES=$(bashio::config 'deny_mac_addresses' )
DEBUG=$(bashio::config 'debug' )
HOSTAPD_CONFIG_OVERRIDE=$(bashio::config 'hostapd_config_override' )

echo "Starting Hass.io Access Point Addon"

# Setup interface
logger "# Setup interface:" 1
logger "Creating Bridge" 1
ip link add name br0 type bridge
logger "Stopping Network inferfaces" 1
ip link set $WIFI_INTERFACE down
ip link set $ETH_INTERFACE down
logger "Assigning to bridge" 1
ip link set $ETH_INTERFACE master br0
ip link set $WIFI_INTERFACE master br0
logger "Starting bridge" 1
ip link set br0 up
logger "Starting interfaces" 1
ip link set $ETH_INTERFACE up
ip link set $WIFI_INTERFACE up

# Enforces required env variables
required_vars=(ssid wpa_passphrase)
for required_var in "${required_vars[@]}"; do
    bashio::config.require $required_var "An AP cannot be created without this information"
done

if [ ${#WPA_PASSPHRASE} -lt 8 ] ; then
    bashio::exit.nok "The WPA password must be at least 8 characters long!"
fi

# Setup hostapd.conf
logger "# Setup hostapd:" 1
logger "Add to hostapd.conf: ssid=$SSID" 1
echo "ssid=$SSID"$'\n' >> /hostapd.conf
logger "Add to hostapd.conf: wpa_passphrase=********" 1
echo "wpa_passphrase=$WPA_PASSPHRASE"$'\n' >> /hostapd.conf
logger "Add to hostapd.conf: ignore_broadcast_ssid=$HIDE_SSID" 1
echo "ignore_broadcast_ssid=$HIDE_SSID"$'\n' >> /hostapd.conf

### MAC address filtering
## Allow is more restrictive, so we prioritise that and set
## macaddr_acl to 1, and add allowed MAC addresses to hostapd.allow
if [ ${#ALLOW_MAC_ADDRESSES} -ge 1 ]; then
    logger "Add to hostapd.conf: macaddr_acl=1" 1
    echo "macaddr_acl=1"$'\n' >> /hostapd.conf
    ALLOWED=($ALLOW_MAC_ADDRESSES)
    logger "# Setup hostapd.allow:" 1
    logger "Allowed MAC addresses:" 0
    for mac in "${ALLOWED[@]}"; do
        echo "$mac"$'\n' >> /hostapd.allow
        logger "$mac" 0
    done
    logger "Add to hostapd.conf: accept_mac_file=/hostapd.allow" 1
    echo "accept_mac_file=/hostapd.allow"$'\n' >> /hostapd.conf
## else set macaddr_acl to 0, and add denied MAC addresses to hostapd.deny
elif [ ${#DENY_MAC_ADDRESSES} -ge 1 ]; then
        logger "Add to hostapd.conf: macaddr_acl=0" 1
        echo "macaddr_acl=0"$'\n' >> /hostapd.conf
        DENIED=($DENY_MAC_ADDRESSES)
        logger "Denied MAC addresses:" 0
        for mac in "${DENIED[@]}"; do
            echo "$mac"$'\n' >> /hostapd.deny
            logger "$mac" 0
        done
        logger "Add to hostapd.conf: accept_mac_file=/hostapd.deny" 1
        echo "deny_mac_file=/hostapd.deny"$'\n' >> /hostapd.conf
## else set macaddr_acl to 0, with blank allow and deny files
else
    logger "Add to hostapd.conf: macaddr_acl=0" 1
    echo "macaddr_acl=0"$'\n' >> /hostapd.conf
fi

# Add interface to hostapd.conf
logger "Add to hostapd.conf: interface=$WIFI_INTERFACE" 1
echo "interface=$WIFI_INTERFACE"$'\n' >> /hostapd.conf
echo "bridge=br0"$'\n' >> /hostapd.conf

# Append override options to hostapd.conf
if [ ${#HOSTAPD_CONFIG_OVERRIDE} -ge 1 ]; then
    logger "# Custom hostapd config options:" 0
    HOSTAPD_OVERRIDES=($HOSTAPD_CONFIG_OVERRIDE)
    for override in "${HOSTAPD_OVERRIDES[@]}"; do
        echo "$override"$'\n' >> /hostapd.conf
        logger "Add to hostapd.conf: $override" 0
    done
fi

logger "## Starting hostapd daemon" 1
# If debug level is greater than 1, start hostapd in debug mode
if [ $DEBUG -gt 1 ]; then
    hostapd -d /hostapd.conf & wait ${!}
else
    hostapd /hostapd.conf & wait ${!}
fi
