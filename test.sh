#!/bin/bash
# better-cloudflare-ip

function bettercloudflareip(){
read -p "Please set the expected bandwidth size (minimum=1)Mbps:" bandwidth
read -p "Please set the number of test processes (default 10, maximum 50):" tasknum
if [ -z "$bandwidth" ]
then
	bandwidth=1
fi
if [ $bandwidth -eq 0 ]
then
	bandwidth=1
fi
if [ -z "$tasknum" ]
then
	tasknum=10
fi
if [ $tasknum -eq 0 ]
then
	echo "The number of processes cannot be 0, it is automatically set to the default value"
	tasknum=10
fi
if [ $tasknum -gt 50 ]
then
	echo "Exceeded the maximum process limit, automatically set to the maximum"
	tasknum=50
fi
speed=$[$bandwidth*128*1024]
starttime=$(date +%s)
cloudflaretest
realbandwidth=$[$max/128]
endtime=$(date +%s)
echo "Geting details from server"
unset temp
if [ "$ips" == "ipv4" ]
then
	if [ $tls == 1 ]
	then
		temp=($(curl --resolve $domain:443:$anycast --retry 1 -s https://$domain/cdn-cgi/trace --connect-timeout 2 --max-time 3))
	else
		temp=($(curl -x $anycast:80 --retry 1 -s http://$domain/cdn-cgi/trace --connect-timeout 2 --max-time 3))
	fi
else
	if [ $tls == 1 ]
	then
		temp=($(curl --resolve $domain:443:$anycast --retry 1 -s https://$domain/cdn-cgi/trace --connect-timeout 2 --max-time 3))
	else
		temp=($(curl -x [$anycast]:80 --retry 1 -s http://$domain/cdn-cgi/trace --connect-timeout 2 --max-time 3))
	fi
fi
if [ $(echo ${temp[@]} | sed -e 's/ /\n/g' | grep colo= | wc -l) == 0 ]
then
	publicip=timedOut
	colo=timedOut
else
	publicip=$(echo ${temp[@]} | sed -e 's/ /\n/g' | grep ip= | cut -f 2- -d'=')
	colo=$(grep -w "($(echo ${temp[@]} | sed -e 's/ /\n/g' | grep colo= | cut -f 2- -d'='))" colo.txt | awk -F"-" '{print $1}')
fi
clear
echo "preferred IP $anycast"
echo "Your public IP $publicip"
if [ $tls == 1 ]
then
	echo "Support ports: 443 2053 2083 2087 2096 8443"
else
	echo "Support ports: 80 8080 8880 2052 2082 2086 2095"
fi
echo "Set the bandwidth $bandwidth Mbps"
echo "Real BW $realbandwidth Mbps"
echo "Best Speed $max kB/s"
echo "Ping $avgms 毫秒"
echo "Data Cente $colo"
echo "Total time spent $[$endtime-$starttime] 秒"
}

function rtthttps(){
avgms=0
n=1
for ip in `cat rtt/$1.txt`
do
	while true
	do
		if [ $n -le 3 ]
		then
			rsp=$(curl --resolve $domain:443:$ip https://$domain/cdn-cgi/trace -o /dev/null -s --connect-timeout 1 --max-time 3 -w %{time_connect}_%{http_code})
			if [ $(echo $rsp | awk -F_ '{print $2}') != 200 ]
			then
				avgms=0
				n=1
				break
			else
				avgms=$[$(echo $rsp | awk -F_ '{printf ("%d\n",$1*1000000)}')+$avgms]
				n=$[$n+1]
			fi
		else
			avgms=$[$avgms/3000]
			if [ $avgms -lt 10 ]
			then
				echo 00$avgms $ip >> rtt/$1.log
			elif [ $avgms -ge 10 ] && [ $avgms -lt 100 ]
			then
				echo 0$avgms $ip >> rtt/$1.log
			else
				echo $avgms $ip >> rtt/$1.log
			fi
			avgms=0
			n=1
			break
		fi
	done
done
rm -rf rtt/$1.txt
}

function rtthttp(){
avgms=0
n=1
for ip in `cat rtt/$1.txt`
do
	while true
	do
		if [ $n -le 3 ]
		then
			if [ $(echo $ip | grep : | wc -l) == 0 ]
			then
				rsp=$(curl -x $ip:80 http://$domain/cdn-cgi/trace -o /dev/null -s --connect-timeout 1 --max-time 3 -w %{time_connect}_%{http_code})
			else
				rsp=$(curl -x [$ip]:80 http://$domain/cdn-cgi/trace -o /dev/null -s --connect-timeout 1 --max-time 3 -w %{time_connect}_%{http_code})
			fi
			if [ $(echo $rsp | awk -F_ '{print $2}') != 200 ]
			then
				avgms=0
				n=1
				break
			else
				avgms=$[$(echo $rsp | awk -F_ '{printf ("%d\n",$1*1000000)}')+$avgms]
				n=$[$n+1]
			fi
		else
			avgms=$[$avgms/3000]
			if [ $avgms -lt 10 ]
			then
				echo 00$avgms $ip >> rtt/$1.log
			elif [ $avgms -ge 10 ] && [ $avgms -lt 100 ]
			then
				echo 0$avgms $ip >> rtt/$1.log
			else
				echo $avgms $ip >> rtt/$1.log
			fi
			avgms=0
			n=1
			break
		fi
	done
done
rm -rf rtt/$1.txt
}

function speedtesthttps(){
rm -rf log.txt speed.txt
curl --resolve $domain:443:$1 https://$domain/$file -o /dev/null --connect-timeout 1 --max-time 10 > log.txt 2>&1
cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep -v 'k\|M' >> speed.txt
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep k | sed 's/k//g'`
do
	k=$i
	k=$[$k*1024]
	echo $k >> speed.txt
done
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep M | sed 's/M//g'`
do
	i=$(echo | awk '{print '$i'*10 }')
	M=$i
	M=$[$M*1024*1024/10]
	echo $M >> speed.txt
done
max=0
for i in `cat speed.txt`
do
	if [ $i -ge $max ]
	then
		max=$i
	fi
done
rm -rf log.txt speed.txt
echo $max
}

function speedtesthttp(){
rm -rf log.txt speed.txt
if [ $(echo $1 | grep : | wc -l) == 0 ]
then
	curl -x $1:80 http://$domain/$file -o /dev/null --connect-timeout 1 --max-time 10 > log.txt 2>&1
else
	curl -x [$1]:80 http://$domain/$file -o /dev/null --connect-timeout 1 --max-time 10 > log.txt 2>&1
fi
cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep -v 'k\|M' >> speed.txt
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep k | sed 's/k//g'`
do
	k=$i
	k=$[$k*1024]
	echo $k >> speed.txt
done
for i in `cat log.txt | tr '\r' '\n' | awk '{print $NF}' | sed '1,3d;$d' | grep M | sed 's/M//g'`
do
	i=$(echo | awk '{print '$i'*10 }')
	M=$i
	M=$[$M*1024*1024/10]
	echo $M >> speed.txt
done
max=0
for i in `cat speed.txt`
do
	if [ $i -ge $max ]
	then
		max=$i
	fi
done
rm -rf log.txt speed.txt
echo $max
}

function cloudflaretest(){
while true
do
	while true
	do
		rm -rf rtt rtt.txt log.txt speed.txt
		mkdir rtt
		echo "Being generated $ips"
		unset temp
		if [ "$ips" == "ipv4" ]
		then
			n=0
			iplist=100
			while true
			do
				for i in `awk 'BEGIN{srand()} {print rand()"\t"$0}' $filename | sort -n | awk '{print $2} NR=='$iplist' {exit}' | awk -F\. '{print $1"."$2"."$3}'`
				do
					temp[$n]=$(echo $i.$(($RANDOM%256)))
					n=$[$n+1]
				done
				if [ $n -ge $iplist ]
				then
					break
				fi
			done
			while true
			do
				if [ $(echo ${temp[@]} | sed -e 's/ /\n/g' | sort -u | wc -l) -ge $iplist ]
				then
					break
				else
					for i in `awk 'BEGIN{srand()} {print rand()"\t"$0}' $filename | sort -n | awk '{print $2} NR=='$[$iplist-$(echo ${temp[@]} | sed -e 's/ /\n/g' | sort -u | wc -l)]' {exit}' | awk -F\. '{print $1"."$2"."$3}'`
					do
						temp[$n]=$(echo $i.$(($RANDOM%256)))
						n=$[$n+1]
					done
				fi
			done
		else
			n=0
			iplist=100
			while true
			do
				for i in `awk 'BEGIN{srand()} {print rand()"\t"$0}' $filename | sort -n | awk '{print $2} NR=='$iplist' {exit}' | awk -F: '{print $1":"$2":"$3}'`
				do
					temp[$n]=$(echo $i:$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))))
					n=$[$n+1]
				done
				if [ $n -ge $iplist ]
				then
					break
				fi
			done
			while true
			do
				if [ $(echo ${temp[@]} | sed -e 's/ /\n/g' | sort -u | wc -l) -ge $iplist ]
				then
					break
				else
					for i in `awk 'BEGIN{srand()} {print rand()"\t"$0}' $filename | sort -n | awk '{print $2} NR=='$[$iplist-$(echo ${temp[@]} | sed -e 's/ /\n/g' | sort -u | wc -l)]' {exit}' | awk -F: '{print $1":"$2":"$3}'`
					do
						temp[$n]=$(echo $i:$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))):$(printf '%x\n' $(($RANDOM*2+$RANDOM%2))))
						n=$[$n+1]
					done
				fi
			done
		fi
		ipnum=$(echo ${temp[@]} | sed -e 's/ /\n/g' | sort -u | wc -l)
		if [ $tasknum == 0 ]
		then
			tasknum=1
		fi
		if [ $ipnum -lt $tasknum ]
		then
			tasknum=$ipnum
		fi
		n=1
		for i in `echo ${temp[@]} | sed -e 's/ /\n/g' | sort -u`
		do
			echo $i>>rtt/$n.txt
			if [ $n == $tasknum ]
			then
				n=1
			else
				n=$[$n+1]
			fi
		done
		n=1
		while true
		do
			if [ $tls == 1 ]
			then
				rtthttps $n &
			else
				rtthttp $n &
			fi
			if [ $n == $tasknum ]
			then
				break
			else
				n=$[$n+1]
			fi
		done
		while true
		do
			n=$(ls rtt | grep txt | wc -l)
			if [ $n -ne 0 ]
			then
				echo "$(date +'%H:%M:%S') Wait for the RTT test,Remaining $n"
			else
				echo "$(date +'%H:%M:%S') RTT test completed"
				break
			fi
			sleep 1
		done
		n=$(ls rtt | grep log | wc -l)
		if [ $n == 0 ]
		then
			echo "All current IPs have RTT packet loss"
			echo "Continue with new RTT test"
		else
			cat rtt/*.log > rtt.txt
			status=0
			echo "IP address to be tested"
			cat rtt.txt | sort | awk '{print $2" Round-trip delay "$1" ms"}'
			for i in `cat rtt.txt | sort | awk '{print $1"_"$2}'`
			do
				avgms=$(echo $i | awk -F_ '{print $1}')
				ip=$(echo $i | awk -F_ '{print $2}')
				echo "currently testing $ip"
				if [ $tls == 1 ]
				then
					max=$(speedtesthttps $ip)
				else
					max=$(speedtesthttp $ip)
				fi
				if [ $max -ge $speed ]
				then
					status=1
					anycast=$ip
					max=$[$max/1024]
					echo "$ip peak speed $max kB/s"
					rm -rf rtt rtt.txt
					break
				else
				max=$[$max/1024]
				echo "$ip peak speed $max kB/s"
				fi
			done
			if [ $status == 1 ]
			then
				break
			fi
		fi
	done
		break
done
}

function singlehttps(){
read -p "Enter The IP For Test: " ip
read -p "Port(Default 443):     " port
if [ -z "$ip" ]
then
	echo "No IP Detected"
fi
if [ -z "$port" ]
then
	port=443
fi
echo "Testing speed For $ip : $port"
speed_download=$(curl --resolve $domain:$port:$ip https://$domain:$port/$file -o /dev/null --connect-timeout 5 --max-time 15 -w %{speed_download} | awk -F\. '{printf ("%d\n",$1/1024)}')
}

function singlehttp(){
read -p "Enter The IP For Test: " ip
read -p "Port(Default 443):     " port
if [ -z "$ip" ]
then
	echo "No IP Detected"
fi
if [ -z "$port" ]
then
	port=80
fi
echo "Testing speed For $ip : $port"
if [ $(echo $ip | grep : | wc -l) == 0 ]
then
	speed_download=$(curl -x $ip:$port http://$domain:$port/$file -o /dev/null --connect-timeout 5 --max-time 15 -w %{speed_download} | awk -F\. '{printf ("%d\n",$1/1024)}')
else
	speed_download=$(curl -x [$ip]:$port http://$domain:$port/$file -o /dev/null --connect-timeout 5 --max-time 15 -w %{speed_download} | awk -F\. '{printf ("%d\n",$1/1024)}')
fi
}

#function datacheck(){
#clear
#echo "如果这些下面这些文件下载失败,可以手动访问网址下载保存至同级目录"
#echo "https://www.baipiao.eu.org/cloudflare/colo 另存为 colo.txt"
#echo "https://www.baipiao.eu.org/cloudflare/url 另存为 url.txt"
#echo "https://www.baipiao.eu.org/cloudflare/ips-v4 另存为 ips-v4.txt"
#echo "https://www.baipiao.eu.org/cloudflare/ips-v6 另存为 ips-v6.txt"
#while true
#do
#	if [ ! -f "colo.txt" ]
#	then
#		echo "从服务器下载数据中心信息 colo.txt"
#		curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/colo -o colo.txt
#	elif [ ! -f "url.txt" ]
#	then
#		echo "从服务器下载测速文件地址 url.txt"
#		curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/url -o url.txt
#	elif [ ! -f "ips-v4.txt" ]
#	then
#		echo "从服务器下载IPV4数据 ips-v4.txt"
#		curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/ips-v4 -o ips-v4.txt
#	elif [ ! -f "ips-v6.txt" ]
#	then
#		echo "从服务器下载IPV6数据 ips-v6.txt"
#		curl --retry 2 -s https://www.baipiao.eu.org/cloudflare/ips-v6 -o ips-v6.txt
#	else
#		break
#	fi
#done
#}
#datacheck

url=$(sed -n '1p' url.txt)
domain=$(echo $url | cut -f 1 -d'/')
file=$(echo $url | cut -f 2- -d'/')
clear
while true
do
	echo "1. IPV4(TLS)"
	echo "2. IPV4"
	echo "3. IPV6(TLS)"
	echo "4. IPV6"
	echo "5. single IP speed(TLS)"
	echo "6. single IP speed test"
	echo "7. Clear Cache"
	echo "8. Update data"
	echo -e "0. Exit\n"
	read -p "Your Choice(Default 0): " menu
	if [ -z "$menu" ]
	then
		menu=0
	fi
	if [ $menu == 0 ]
	then
		clear
		echo "Successful exit"
		break
	fi
	if [ $menu == 1 ]
	then
		ips=ipv4
		filename=ips-v4.txt
		tls=1
		bettercloudflareip
		break
	fi
	if [ $menu == 2 ]
	then
		ips=ipv4
		filename=ips-v4.txt
		tls=0
		bettercloudflareip
		break
	fi
	if [ $menu == 3 ]
	then
		ips=ipv6
		filename=ips-v6.txt
		tls=1
		bettercloudflareip
		break
	fi
	if [ $menu == 4 ]
	then
		ips=ipv6
		filename=ips-v6.txt
		tls=0
		bettercloudflareip
		break
	fi
	if [ $menu == 5 ]
	then
		singlehttps
		clear
		echo "$ip average speed $speed_download kB/s"
	fi
	if [ $menu == 6 ]
	then
		singlehttp
		clear
		echo "$ip average speed $speed_download kB/s"
	fi
	if [ $menu == 7 ]
	then
		rm -rf rtt rtt.txt log.txt speed.txt
		clear
		echo "cache has been cleared"
	fi
	if [ $menu == 8 ]
	then
		rm -rf colo.txt url.txt ips-v4.txt ips-v6.txt
		datacheck
		clear
	fi
done
