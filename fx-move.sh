#!/usr/bin/env bash

sudo chown root:root fs-shared.sh
sudo mv fs-shared.sh /usr/local/lib

sudo chown root:root fs-*.sh
sudo chmod +x fs-*.sh
for file in fs-*.sh; do
	sudo mv "$file" "/usr/local/bin/${file%.sh}"
done

sudo bash fx-sha256.sh
rm fx-sha256.sh
rm fx-move.sh