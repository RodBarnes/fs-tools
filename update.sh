# Convenience script used to convert from v1 to v2 and v3 of the
# backup drive structure.
snapshot="$1"

# v1 to v3
pattern="^\(.+\)\s+(.+)"
desc=$(cat "$snapshot/comment.txt")
if [[ $desc =~ $pattern ]]; then
    comment="${BASH_REMATCH[1]}"
    echo "Group 1: $comment"
else
    comment="$note"
fi
hostname=$(hostname -s)
device=$(findmnt -n -o SOURCE /)
uuid=$(blkid -s UUID -o value "$device")

# v2 to v3
# comment=$(jq -r '.comment' "$snapshot/info.json")
# hostname=$(jq -r '.hostname' "$snapshot/info.json")
# device=$(jq -r '.device' "$snapshot/info.json")
# uuid=$(jq -r '.uuid' "$snapshot/info.json")

# All
machine_id=$(cat /etc/machine-id)
json=$(jq -nc --arg comment "$comment" --arg device "$device" --arg uuid "$uuid" --arg hostname "$hostname" --arg machine_id "$machine_id" '{comment: $comment, device: $device, uuid: $uuid, hostname: $hostname, machine_id: $machine_id}')

echo "comment=$comment"
echo "hostname=$hostname"
echo "device=$device"
echo "uuid=$uuid"
echo "machine_id=$machine_id"
echo "json=$json"

echo $json | sudo tee "$snapshot/info.json" > /dev/null


