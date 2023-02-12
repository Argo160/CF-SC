url=$(sed -n '1p' url.txt)
domain=$(echo $url | cut -f 1 -d'/')
file=$(echo $url | cut -f 2- -d'/')
clear

read -p "Enter The IP For Test: " ip
port=443
if [ -z "$ip" ]
then
	echo "IP not entered"
fi
echo "Testing speed For $ip : $port"
speed_download=$(curl --resolve $domain:$port:$ip https://$domain:$port/$file -o /dev/null --connect-timeout 5 --max-time 15 -w %{speed_download} | awk -F\. '{printf ("%d\n",$1/1024)}')
echo "$ip Average speed $speed_download kB/s"
