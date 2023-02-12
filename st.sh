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
speed_download=$(curl --resolve $domain:$port:$ip https://$domain:$port/$file -o /dev/null --connect-timeout 5 --max-time 15 -w %{speed_download} | awk -F\. '{printf ("%d\n",$1/1024)}')

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
max=$(speedtesthttps $ip)
max=$[$max/1024]
echo "$ip Best Speed $max kB/s"
