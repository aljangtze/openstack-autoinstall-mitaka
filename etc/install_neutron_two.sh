#！/bin/bash
#log function
NAMEHOST=$HOSTNAME
if [  -e $PWD/lib/mitaka-log.sh ]
then	
	source $PWD/lib/mitaka-log.sh
else
	echo -e " $PWD/mitaka-log.sh is not exist. "
	exit 1
fi
#input variable
if [  -e $PWD/lib/installrc ]
then	
	source $PWD/lib/installrc 
else
	echo -e " $PWD/lib/installr is not exist. "
	exit 1
fi
if [  -e /etc/openstack-mitaka_tag/computer.tag  ]
then
	echo -e " Oh no ! you can't execute this script on computer node.  "
	log_error "Oh no ! you can't execute this script on computer node. "
	exit 1 
fi

#不需要先安装cinder
#if [ -f  /etc/openstack-mitaka_tag/install_cinder.tag ]
#then 
#	log_info "cinder have installed ."
#else
#	echo -e "[41;37m you should install cinder first. "
#	exit
#fi

if [ -f  /etc/openstack-mitaka_tag/install_neutron.tag ]
then 
	echo -e "you haved install neutron "
	log_info "you haved install neutron."	
	exit
fi

#create neutron databases 
function  fn_create_neutron_database () {
mysql -uroot -p${DATABASE_PASSWORD} -e "CREATE DATABASE neutron;" &&  \
mysql -uroot -p${DATABASE_PASSWORD} -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '${ALL_PASSWORD}';" && \
mysql -uroot -p${DATABASE_PASSWORD} -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '${ALL_PASSWORD}';" 
fn_log "create  database neutron"
}

#检查是否创建成功
mysql -uroot -p${DATABASE_PASSWORD} -e "show databases ;" >test 
DATABASENEUTRON=`cat test | grep neutron`
rm -rf test 
if [ ${DATABASENEUTRON}x = neutronx ]
then
	log_info "neutron database had installed."
else
	fn_create_neutron_database
fi

unset http_proxy https_proxy ftp_proxy no_proxy 

#检查是否存在neutron用户，如果不存在，重新创建
source /root/admin-openrc.sh
USER_NEUTRON=`openstack user list | grep neutron | awk -F "|" '{print$3}' | awk -F " " '{print$1}'`
if [ ${USER_NEUTRON}x = neutronx ]
then
	log_info "openstack user had created  neutron"
else
	openstack user create --domain default  neutron  --password ${ALL_PASSWORD}
	fn_log "openstack user create neutron  --password ${ALL_PASSWORD}"
	openstack role add --project service --user neutron admin
	fn_log "openstack role add --project service --user neutron admin"
fi

SERVICE_NEUTRON=`openstack service list | grep neutron | awk -F "|" '{print$3}' | awk -F " " '{print$1}'`
if [  ${SERVICE_NEUTRON}x = neutronx ]
then 
	log_info "openstack service create neutron."
else
	openstack service create --name neutron --description "OpenStack Networking" network
	fn_log "openstack service create --name neutron --description "OpenStack Networking" network"
fi

#检查端点服务是否创建 
ENDPOINT_LIST_INTERNAL=`openstack endpoint list  | grep network  |grep internal | wc -l`
ENDPOINT_LIST_provider=`openstack endpoint list | grep network   |grep provider | wc -l`
ENDPOINT_LIST_ADMIN=`openstack endpoint list | grep network   |grep admin | wc -l`
if [  ${ENDPOINT_LIST_INTERNAL}  -eq 0  ]  && [ ${ENDPOINT_LIST_provider}  -eq  0   ] &&  [ ${ENDPOINT_LIST_ADMIN} -eq 0  ]
then
	openstack endpoint create --region RegionOne   network public http://${NAMEHOST}:9696  &&  \
	openstack endpoint create --region RegionOne   network internal http://${NAMEHOST}:9696 &&  \
	openstack endpoint create --region RegionOne   network admin http://${NAMEHOST}:9696
	fn_log "openstack endpoint create --region RegionOne   network provider http://${NAMEHOST}:9696  &&   openstack endpoint create --region RegionOne   network internal http://${NAMEHOST}:9696 &&   openstack endpoint create --region RegionOne   network admin http://${NAMEHOST}:9696"
else	
	log_info "openstack endpoint create neutron."
fi


#test network
function fn_test_network () {
if [ -f $PWD/lib/proxy.sh ]
then 
	source  $PWD/lib/proxy.sh
fi
curl www.baidu.com >/dev/null   
fn_log "curl www.baidu.com >/dev/null "
}



if  [ -f /etc/yum.repos.d/repo.repo ]
then
	log_info " use local yum."
else 
	fn_test_network
fi


#Self-service networks
yum install openstack-neutron openstack-neutron-ml2   openstack-neutron-linuxbridge ebtables -y 
fn_log "yum clean all && yum install openstack-neutron openstack-neutron-ml2   openstack-neutron-linuxbridge ebtables -y"
[ -f /etc/neutron/neutron.conf_bak ] || cp -a  /etc/neutron/neutron.conf /etc/neutron/neutron.conf_bak 
openstack-config --set  /etc/neutron/neutron.conf database connection   mysql+pymysql://neutron:${ALL_PASSWORD}@${NAMEHOST}/neutron &&   \
openstack-config --set  /etc/neutron/neutron.conf DEFAULT core_plugin  ml2  &&   \
openstack-config --set  /etc/neutron/neutron.conf DEFAULT service_plugins  router  &&   \
openstack-config --set  /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips  True  &&   \
openstack-config --set  /etc/neutron/neutron.conf DEFAULT rpc_backend  rabbit  &&   \
openstack-config --set  /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_host  ${NAMEHOST}  &&   \
openstack-config --set  /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_userid  openstack  &&   \
openstack-config --set  /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_password  ${ALL_PASSWORD}  &&   \
openstack-config --set  /etc/neutron/neutron.conf DEFAULT auth_strategy  keystone  &&   \
openstack-config --set  /etc/neutron/neutron.conf keystone_authtoken auth_uri  http://${NAMEHOST}:5000  &&   \
openstack-config --set  /etc/neutron/neutron.conf keystone_authtoken auth_url  http://${NAMEHOST}:35357  
openstack-config --set  /etc/neutron/neutron.conf keystone_authtoken memcached_servers  ${NAMEHOST}:11211 &&   \
openstack-config --set  /etc/neutron/neutron.conf keystone_authtoken auth_type  password  &&   \
openstack-config --set  /etc/neutron/neutron.conf keystone_authtoken project_domain_name  default  &&   \
openstack-config --set  /etc/neutron/neutron.conf keystone_authtoken user_domain_name  default  &&   \
openstack-config --set  /etc/neutron/neutron.conf keystone_authtoken project_name  service  &&   \
openstack-config --set  /etc/neutron/neutron.conf keystone_authtoken username  neutron  &&   \
openstack-config --set  /etc/neutron/neutron.conf keystone_authtoken password  ${ALL_PASSWORD}  &&   \
openstack-config --set  /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes  True  &&   \
openstack-config --set  /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes  True  &&   \
openstack-config --set  /etc/neutron/neutron.conf nova auth_url  http://${NAMEHOST}:35357  &&   \
openstack-config --set  /etc/neutron/neutron.conf nova auth_type  password  &&   \
openstack-config --set  /etc/neutron/neutron.conf nova project_domain_name  default  &&   \
openstack-config --set  /etc/neutron/neutron.conf nova user_domain_name  default  &&   \
openstack-config --set  /etc/neutron/neutron.conf nova region_name  RegionOne  &&   \
openstack-config --set  /etc/neutron/neutron.conf nova project_name  service  &&   \
openstack-config --set  /etc/neutron/neutron.conf nova username  nova  &&   \
openstack-config --set  /etc/neutron/neutron.conf nova password  ${ALL_PASSWORD}  &&   \
openstack-config --set  /etc/neutron/neutron.conf oslo_concurrency lock_path  /var/lib/neutron/tmp  &&   \
openstack-config --set  /etc/neutron/neutron.conf DEFAULT verbose  True
fn_log "config /etc/neutron/neutron.conf "

[ -f  /etc/neutron/plugins/ml2/ml2_conf.ini_bak ] || cp -a   /etc/neutron/plugins/ml2/ml2_conf.ini  /etc/neutron/plugins/ml2/ml2_conf.ini_bak 
openstack-config --set   /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers  flat,vlan,vxlan && \
openstack-config --set   /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers  linuxbridge,l2population && \
openstack-config --set   /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers  port_security && \
openstack-config --set   /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types  vxlan && \
openstack-config --set   /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks  provider && \
openstack-config --set   /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges  1:1000 && \
openstack-config --set   /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset  True
fn_log "config /etc/neutron/plugins/ml2/ml2_conf.ini "

SECONF_ETH=${NET_DEVICE_NAME}
FIRST_ETH_IP=${MANAGER_IP}
[ -f  /etc/neutron/plugins/ml2/linuxbridge_agent.ini_bak ] || cp -a   /etc/neutron/plugins/ml2/linuxbridge_agent.ini   /etc/neutron/plugins/ml2/linuxbridge_agent.ini_bak 
openstack-config --set   /etc/neutron/plugins/ml2/linuxbridge_agent.ini  linux_bridge physical_interface_mappings  provider:${SECONF_ETH} && \
openstack-config --set   /etc/neutron/plugins/ml2/linuxbridge_agent.ini  vxlan  enable_vxlan  True && \
openstack-config --set   /etc/neutron/plugins/ml2/linuxbridge_agent.ini  vxlan  local_ip  ${FIRST_ETH_IP} && \
openstack-config --set   /etc/neutron/plugins/ml2/linuxbridge_agent.ini  vxlan l2_population  True && \
openstack-config --set   /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup  enable_security_group  True && \
openstack-config --set   /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup  firewall_driver  neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
fn_log "config /etc/neutron/plugins/ml2/linuxbridge_agent.ini"

[ -f   /etc/neutron/l3_agent.ini_bak ] || cp -a    /etc/neutron/l3_agent.ini    /etc/neutron/l3_agent.ini_bak 
openstack-config --set  /etc/neutron/l3_agent.ini  DEFAULT     interface_driver  neutron.agent.linux.interface.BridgeInterfaceDriver && \
openstack-config --set   /etc/neutron/l3_agent.ini  DEFAULT     external_network_bridge    && \
openstack-config --set  /etc/neutron/l3_agent.ini  DEFAULT     verbose  True  
fn_log "config /etc/neutron/l3_agent.ini "

[ -f   /etc/neutron/dhcp_agent.ini_bak ] || cp -a    /etc/neutron/dhcp_agent.ini    /etc/neutron/dhcp_agent.ini_bak 
openstack-config --set  /etc/neutron/dhcp_agent.ini  DEFAULT     interface_driver  neutron.agent.linux.interface.BridgeInterfaceDriver    && \
openstack-config --set  /etc/neutron/dhcp_agent.ini  DEFAULT     dhcp_driver  neutron.agent.linux.dhcp.Dnsmasq   && \
openstack-config --set  /etc/neutron/dhcp_agent.ini  DEFAULT     enable_isolated_metadata  True   && \
openstack-config --set  /etc/neutron/dhcp_agent.ini  DEFAULT     verbose  True   
fn_log "config /etc/neutron/dhcp_agent.ini "

openstack-config --set  /etc/nova/nova.conf  neutron url  http://${NAMEHOST}:9696 && \
openstack-config --set  /etc/nova/nova.conf  neutron auth_url  http://${NAMEHOST}:35357 && \
openstack-config --set  /etc/nova/nova.conf  neutron auth_type  password && \
openstack-config --set  /etc/nova/nova.conf  neutron project_domain_name  default && \
openstack-config --set  /etc/nova/nova.conf  neutron user_domain_name  default && \
openstack-config --set  /etc/nova/nova.conf  neutron region_name  RegionOne && \
openstack-config --set  /etc/nova/nova.conf  neutron project_name service && \
openstack-config --set  /etc/nova/nova.conf  neutron username  neutron && \
openstack-config --set  /etc/nova/nova.conf  neutron password  ${ALL_PASSWORD} && \
openstack-config --set  /etc/nova/nova.conf  neutron service_metadata_proxy  True && \
openstack-config --set  /etc/nova/nova.conf  neutron metadata_proxy_shared_secret  ${ALL_PASSWORD} && \
fn_log "config /etc/nova/nova.conf"



echo "dhcp-option-force=26,1450" >/etc/neutron/dnsmasq-neutron.conf
fn_log "echo "dhcp-option-force=26,1450" >/etc/neutron/dnsmasq-neutron.conf"

[ -f /etc/neutron/metadata_agent.ini_bak-2 ] || cp -a  /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini_bak-2 && \
openstack-config --set  /etc/neutron/metadata_agent.ini  DEFAULT nova_metadata_ip  ${NAMEHOST}   && \
openstack-config --set  /etc/neutron/metadata_agent.ini  DEFAULT metadata_proxy_shared_secret  ${ALL_PASSWORD} && \
openstack-config --set  /etc/neutron/metadata_agent.ini  DEFAULT verbose  True
fn_log "config /etc/neutron/metadata_agent.ini"



rm -rf /etc/neutron/plugin.ini && ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
fn_log "rm -rf /etc/neutron/plugin.ini && ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini"


su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf   --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
fn_log "su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf   --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron"

systemctl restart openstack-nova-api.service
fn_log "systemctl restart openstack-nova-api.service"
systemctl enable neutron-server.service   neutron-linuxbridge-agent.service neutron-dhcp-agent.service   neutron-metadata-agent.service &&  systemctl start neutron-server.service   neutron-linuxbridge-agent.service neutron-dhcp-agent.service   neutron-metadata-agent.service
fn_log "systemctl enable neutron-server.service   neutron-linuxbridge-agent.service neutron-dhcp-agent.service   neutron-metadata-agent.service &&  systemctl start neutron-server.service   neutron-linuxbridge-agent.service neutron-dhcp-agent.service   neutron-metadata-agent.service"
systemctl enable neutron-l3-agent.service && systemctl start neutron-l3-agent.service
fn_log "systemctl enable neutron-l3-agent.service && systemctl start neutron-l3-agent.service"


#到以上neutron配置完毕
#创建网络

SECONF_ETH=${NET_DEVICE_NAME}

#以下操作不知道是干嘛用的
#nmcli connection modify ${SECONF_ETH} ipv4.addresses "${SECOND_NET}" && \
#nmcli connection modify ${SECONF_ETH} ipv4.method manual && \
#nmcli connection up  ${SECONF_ETH} 
#fn_log "nmcli connection modify ${SECONF_ETH} ipv4.addresses "${SECOND_NET}" && nmcli connection modify ${SECONF_ETH} ipv4.method manual && nmcli connection up  ${SECONF_ETH} "



source /root/admin-openrc.sh
neutron ext-list
fn_log "neutron ext-list"
neutron agent-list
fn_log "neutron agent-list"

#Generate a key pair¶
source /root/demo-openrc.sh
KEYPAIR=`nova keypair-list | grep  mykey | awk -F " " '{print$2}'`
if [  ${KEYPAIR}x = mykeyx ]
then
	log_info "keypair had added."
else
	ssh-keygen -t dsa -f ~/.ssh/id_dsa -N ""
	fn_log "ssh-keygen -t dsa -f ~/.ssh/id_dsa -N """
	openstack keypair create --public-key ~/.ssh/id_dsa.pub mykey
	fn_log "openstack keypair create --public-key ~/.ssh/id_dsa.pub mykey"
fi

#Add security group rules
SECRULE=`nova secgroup-list-rules  default | grep 22 | awk -F " " '{print$4}'`
if [ x${SECRULE} = x22 ]
then 
	log_info "port 22 and icmp had add to secgroup."
else
	openstack security group rule create --proto icmp default 
	fn_log "openstack security group rule create --proto icmp default "
	openstack security group rule create --proto tcp --dst-port 22 default
	fn_log "openstack security group rule create --proto tcp --dst-port 22 default"
fi

#创建admin网络，外部网络
source /root/admin-openrc.sh
PUBLIC_NET=`neutron net-list | grep provider |wc -l`
if [ ${PUBLIC_NET}  -eq 0 ]
then
	neutron net-create --shared --provider:physical_network provider   --provider:network_type flat provider
	fn_log "neutron net-create --shared --provider:physical_network provider   --provider:network_type flat provider"
else
	log_info "provider net is exist."
fi

SUB_PUBLIC_NET=`neutron subnet-list | grep provider |wc -l `
if [ ${SUB_PUBLIC_NET}  -eq 0 ]
then
	neutron subnet-create --name provider   --allocation-pool start=${PUBLIC_NET_START},end=${PUBLIC_NET_END}   --dns-nameserver ${NEUTRON_DNS} --gateway ${PUBLIC_NET_GW}    provider ${NEUTRON_PUBLIC_NET}
	fn_log "neutron subnet-create --name provider   --allocation-pool start=${PUBLIC_NET_START},end=${PUBLIC_NET_END}   --dns-nameserver ${NEUTRON_DNS} --gateway ${PUBLIC_NET_GW}    provider ${NEUTRON_PUBLIC_NET}"
else
	log_info "sub_public is exist."
fi

#创建demo网络
source /root/demo-openrc.sh
PRIVATE_NET=`neutron net-list | grep selfservice |wc -l`
if [ ${PRIVATE_NET}  -eq 0 ]
then
	neutron net-create selfservice
	fn_log "neutron net-create selfservice"
else
	log_info "selfservice net is exist."
fi
SUB_PRIVATE_NET=`neutron subnet-list | grep selfservice |wc -l`
if [ ${SUB_PRIVATE_NET}  -eq 0 ]
then
	neutron subnet-create --name selfservice   --dns-nameserver ${PRIVATE_NET_DNS} --gateway ${PRIVATE_NET_GW}  selfservice ${NEUTRON_PRIVATE_NET}
	fn_log "neutron subnet-create --name selfservice   --dns-nameserver ${PRIVATE_NET_DNS}--gateway ${PRIVATE_NET_GW}  selfservice ${NEUTRON_PRIVATE_NET}"
else
	log_info "selfservice subnet is exist."
fi

source /root/admin-openrc.sh
ROUTE_VALUE=`neutron net-show provider | grep router:external | awk -F " "  '{print$4}'`
if [ ${ROUTE_VALUE}x  = Truex  ]
then
	log_info "the value had changed."
else
	neutron net-update provider --router:external
	fn_log "neutron net-update provider --router:external"
fi
source /root/demo-openrc.sh
ROUTE_NU=`neutron router-list | grep router | wc -l`
if [ ${ROUTE_NU}  -eq 0 ]
then
	neutron router-create router
	fn_log "neutron router-create router"
	neutron router-interface-add router selfservice
	fn_log "neutron router-interface-add router selfservice"
	neutron router-gateway-set router provider
	fn_log "neutron router-gateway-set router provider"
else
	log_info "router had created."
fi

source /root/admin-openrc.sh
ip netns
fn_log "ip netns"
neutron router-port-list router
fn_log "neutron router-port-list router"


#重启nova-compute节点，因为没有安装compute,所以这里暂时不启动
#systemctl enable libvirtd.service openstack-nova-compute.service &&  systemctl restart libvirtd.service openstack-nova-compute.service 
#fn_log "systemctl enable libvirtd.service openstack-nova-compute.service &&  systemctl start libvirtd.service openstack-nova-compute.service "

systemctl restart neutron-dhcp-agent  neutron-l3-agent  neutron-linuxbridge-agent  neutron-metadata-agent neutron-server
fn_log "systemctl restart neutron-dhcp-agent  neutron-l3-agent  neutron-linuxbridge-agent  neutron-metadata-agent neutron-server"

if  [ ! -d /etc/openstack-mitaka_tag ]
then 
	mkdir -p /etc/openstack-mitaka_tag  
fi
echo `date "+%Y-%m-%d %H:%M:%S"` >/etc/openstack-mitaka_tag/install_neutron.tag
echo -e " ################################# "
echo -e " ##  Install Neutron Sucessed.#### "
echo -e " ################################# "